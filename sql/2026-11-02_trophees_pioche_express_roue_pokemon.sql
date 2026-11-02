-- Nouveaux trophées : Pioche (5/30/100), Défi express (5/30/100), Roue (10/50/200), Pokémon (10/50/185 cartes différentes). Relançable.
-- À lancer APRÈS sql/2026-11-01_pioche_express.sql et sql/2026-11-01_roue_12h_pokemon.sql (il remplace rc_wheel, rc_pioche, rc_express_claim).
create or replace function public.rc__tpool()
 returns table(kind text, t1 integer, t2 integer, t3 integer, ord integer)
 language sql
 immutable
as $function$
  -- trophées à 3 paliers (bronze, argent, or) ; textes et icônes dans lib/trophies.dart
  values ('packs', 25, 100, 500, 1), ('cards', 100, 400, 1000, 2), ('consoles', 1, 5, 29, 3),
         ('legend', 1, 10, 50, 4), ('fullart', 1, 10, 30, 5), ('fuse', 5, 25, 100, 6),
         ('wins', 10, 50, 200, 7), ('gifts', 10, 50, 200, 8), ('sales', 5, 25, 100, 9),
         ('trades', 5, 25, 100, 10), ('gamedle', 10, 50, 200, 11), ('chest', 1, 5, 20, 12),
         ('sagas', 1, 3, 12, 13), ('days', 7, 30, 100, 14), ('epics', 10, 50, 200, 15), ('holo', 10, 50, 200, 16),
         ('gold', 5, 25, 100, 17), ('recycle', 50, 250, 1000, 18), ('quiz', 50, 250, 1000, 19), ('played', 20, 100, 400, 20),
         ('defis', 10, 50, 200, 21), ('premium', 5, 25, 100, 22), ('buys', 5, 25, 100, 23), ('firsttry', 1, 5, 20, 24),
         ('tourney', 1, 3, 10, 25), ('pioche', 5, 30, 100, 26), ('express', 5, 30, 100, 27),
         ('wheel', 10, 50, 200, 28), ('pokemon', 10, 50, 185, 29),
         ('react', 10, 50, 200, 30), ('craft', 5, 25, 100, 31), ('sagacards', 25, 75, 156, 32) $function$;
;

create or replace function public.rc__tn(p_dev text)
 returns table(kind text, n integer, got integer, t integer[], ord integer)
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  -- progression de chaque trophée : paquets, cartes et consoles lus en direct, le reste compté
  select k.kind,
         case k.kind when 'packs' then p.packs
                     when 'cards' then p.cards
                     when 'consoles' then (select count(*)::int from public.rc_milestones m
                                            where m.device = p_dev and m.step = 100 and m.sys not like 'sg\_%')
                     when 'sagas' then (select count(*)::int from public.rc_milestones m
                                         where m.device = p_dev and m.step = 100 and m.sys like 'sg\_%')
                     when 'days' then p.days
                     when 'react' then (select count(*)::int from public.rc_feed_react r where r.device = p_dev)
                     when 'sagacards' then (select count(*)::int from public.rc_owned o join public.rc_cards cc on cc.id = o.card
                                             where o.device = p_dev and o.qty > 0 and cc.saga is not null and cc.saga <> 'pk')
                     when 'pokemon' then (select count(*)::int from public.rc_owned o join public.rc_cards cc on cc.id = o.card
                                           where o.device = p_dev and o.qty > 0 and cc.saga = 'pk')
                     else coalesce(c.n, 0) end,
         coalesce(g.tier, 0), array[k.t1, k.t2, k.t3], k.ord
    from public.rc__tpool() k
    join public.rc_players p on p.device = p_dev
    left join public.rc_trophy_n c on c.device = p_dev and c.kind = k.kind
    left join public.rc_trophy_got g on g.device = p_dev and g.kind = k.kind $function$;

CREATE OR REPLACE FUNCTION public.rc_wheel(p_device text, p_sig text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  v public.rc_players;
  gold boolean;
  w int[];
  prize int[];
  x float := random() * 100; acc float := 0; seg int := 0; k int;
  r int; f int; c text; is_new boolean; card jsonb := null; pk jsonb := null; ev jsonb := '[]'::jsonb;
  minr int;
begin
  perform public.rc__check(p_sig, p_device || '|wheel');
  select * into v from public.rc_players where device = p_device for update;
  if v.device is null then raise exception 'joueur inconnu'; end if;
  if public.rc__wheel_in(p_device) > 0 then raise exception 'déjà tourné aujourd''hui'; end if;
  -- roue en or : 1er tour du jour de série multiple de 7 (le 2e tour du jour est normal)
  gold := public.rc__wheel_gold(p_device);
  -- 9 cases : 0 petit, 1, 2 carte, 3, 4, 5, 6 rare (épique en or), 7 gros lot (JACKPOT en or), 8 carte Pokémon
  if gold then
    w := array[19, 15, 14, 17, 10, 12, 6, 3, 4];
    prize := array[80, 200, 0, 120, 400, 160, 0, 2000, 0];
  else
    w := array[22, 15, 12, 19, 8, 14, 4, 3, 3];
    prize := array[40, 100, 0, 60, 200, 80, 0, 600, 0];
  end if;
  for k in 1..9 loop
    acc := acc + w[k];
    if x < acc then seg := k - 1; exit; end if;
  end loop;
  perform public.rc__tbump(p_device, 'wheel', 1);  -- trophée : tours de roue
  update public.rc_players set wheel_day = public.rc__today(), wheel_at = now(), coins = coins + prize[seg + 1] where device = p_device;
  -- cases carte (2 = carte, 6 = rare) et, en or, le JACKPOT (7) avec une légendaire
  if seg in (2, 6) or (gold and seg = 7) then
    minr := case when gold and seg = 7 then 4
                 when gold and seg = 6 then 3
                 when gold or seg = 6 then 2
                 else 0 end;
    r := case when minr = 4 then 4 else public.rc__roll(minr) end;
    select id, rarity into c, r from public.rc_cards where rarity <= r and saga is null order by rarity desc, random() limit 1;
    f := public.rc__roll_finish(r);
    is_new := public.rc__is_new(p_device, c, f);
    perform public.rc__give(p_device, c, f, 1);
    card := jsonb_build_object('c', c, 'f', f, 'r', r, 'n', is_new);
    ev := ev || public.rc__milestones(p_device);
    perform public.rc__rescore(p_device);
  elsif seg = 8 then
    -- carte Pokémon au hasard : elle attend dans « Cartes à ranger » (brillante dès la 152)
    select id into c from public.rc_cards where saga = 'pk' order by random() limit 1;
    if c is not null then
      f := case when substr(c, 4)::int >= 152 then 1 else 0 end;
      insert into public.rc_card_stock (device, card, finish, giver_name) values (p_device, c, f, 'Roue de la fortune');
      pk := jsonb_build_object('c', c, 'f', f, 'r', 3, 'stock', true);
    end if;
  end if;
  return jsonb_build_object('seg', seg, 'gain', prize[seg + 1], 'card', card, 'pk', pk, 'events', ev, 'gold', gold,
                            'next_in', 43200,
                            'coins', (select p.coins from public.rc_players p where p.device = p_device));
end $function$;

create or replace function public.rc_pioche(p_device text, p_choice integer, p_sig text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare
  v public.rc_players;
  ids text[] := '{}'; res jsonb := '[]'::jsonb; ev jsonb := '[]'::jsonb;
  i int; r int; c text; f int; sy text; is_new boolean := false; got jsonb := null;
begin
  perform public.rc__check(p_sig, p_device || '|pioche|' || p_choice);
  if p_choice is null or p_choice not between 0 and 4 then raise exception 'choix invalide'; end if;
  select * into v from public.rc_players where device = p_device for update;
  if v.device is null then raise exception 'joueur inconnu'; end if;
  if v.pick_day is not distinct from public.rc__today() then raise exception 'déjà pioché aujourd''hui'; end if;
  -- 5 cartes différentes de tous types (consoles, toutes raretés, finitions) ; ni sagas ni Pokémon
  for i in 0 .. 4 loop
    r := public.rc__roll(0); c := null;
    select id into c from public.rc_cards where rarity = r and saga is null and id <> all(ids) order by random() limit 1;
    if c is null then
      select id, rarity into c, r from public.rc_cards where rarity <= r and saga is null and id <> all(ids) order by rarity desc, random() limit 1;
    end if;
    if c is null then raise exception 'catalogue vide'; end if;
    ids := ids || c;
    f := public.rc__roll_finish(r);
    res := res || jsonb_build_object('c', c, 'f', f, 'r', r);
  end loop;
  update public.rc_players set pick_day = public.rc__today() where device = p_device;
  -- seule la carte choisie est gagnée
  c := res -> p_choice ->> 'c'; f := (res -> p_choice ->> 'f')::int;
  is_new := public.rc__is_new(p_device, c, f);
  perform public.rc__give(p_device, c, f, 1);
  select sys into sy from public.rc_cards where id = c;
  perform public.rc__ev_bump(p_device, 'console', 1, sy);
  if is_new then perform public.rc__wbump(p_device, 'new', 1); end if;
  perform public.rc__tbump(p_device, 'pioche', 1);  -- trophée : pioches du jour
  ev := ev || public.rc__milestones(p_device);
  perform public.rc__rescore(p_device);
  return jsonb_build_object('cards', res, 'pick', p_choice, 'n', is_new, 'events', ev);
end $function$;

create or replace function public.rc_express_claim(p_device text, p_sig text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare e public.rc_express; d record; g jsonb; ev jsonb := '[]'::jsonb; v public.rc_players;
begin
  perform public.rc__check(p_sig, p_device || '|expclaim');
  perform 1 from public.rc_players where device = p_device for update;
  select * into d from public.rc__express_def(public.rc__today());
  select * into e from public.rc_express where device = p_device and day = public.rc__today() for update;
  if e.device is null or e.prog < d.goal then raise exception 'défi express pas fini'; end if;
  if e.claimed then raise exception 'déjà récupéré'; end if;
  update public.rc_express set claimed = true where device = e.device and day = e.day;
  g := public.rc__grant(p_device, d.reward);
  perform public.rc__tbump(p_device, 'express', 1);  -- trophée : défis express
  ev := ev || public.rc__milestones(p_device);
  select * into v from public.rc_players where device = p_device;
  return jsonb_build_object('reward', d.reward, 'coins', v.coins, 'pixels', v.pixels, 'events', ev);
end $function$;

CREATE OR REPLACE FUNCTION public.rc_craft(p_device text, p_card text, p_sig text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  r int; cost int; v public.rc_players; is_new boolean; ev jsonb := '[]'::jsonb;
begin
  perform public.rc__check(p_sig, p_device || '|craft|' || p_card);
  select rarity into r from public.rc_cards where id = p_card;
  if r is null then raise exception 'carte inconnue'; end if;
  if exists (select 1 from public.rc_cards where id = p_card and saga is not null) then raise exception 'carte de saga : seulement dans les paquets'; end if;
  cost := public.rc__craft_cost(r);
  select * into v from public.rc_players where device = p_device for update;
  if v.coins < cost then raise exception 'pas assez de pièces'; end if;
  is_new := public.rc__is_new(p_device, p_card, 0);
  update public.rc_players set coins = coins - cost where device = p_device;
  perform public.rc__tbump(p_device, 'craft', 1);  -- trophée : cartes fabriquées
  perform public.rc__give(p_device, p_card, 0, 1);
  ev := public.rc__milestones(p_device);
  perform public.rc__rescore(p_device);
  return jsonb_build_object('n', is_new, 'coins', (select coins from public.rc_players where device = p_device), 'events', ev);
end $function$;

alter function public.rc_craft(text, text, text) owner to rc_owner;
alter function public.rc__tpool() owner to rc_owner;
alter function public.rc__tn(text) owner to rc_owner;
alter function public.rc_wheel(text, text) owner to rc_owner;
alter function public.rc_pioche(text, integer, text) owner to rc_owner;
alter function public.rc_express_claim(text, text) owner to rc_owner;

notify pgrst, 'reload schema';

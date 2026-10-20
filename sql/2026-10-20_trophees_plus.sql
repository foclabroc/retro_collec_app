-- Trophées : 12 de plus (24 en tout) et vitrine remplie automatiquement par les meilleurs paliers (relançable)
-- À lancer après 2026-10-20_trophees.sql

-- rc__tpool
create or replace function public.rc__tpool()
 returns table(kind text, t1 integer, t2 integer, t3 integer, ord integer)
 language sql
 immutable
as $function$
  -- trophées à 3 paliers (bronze, argent, or) ; textes et icônes dans lib/trophies.dart
  values ('packs', 25, 100, 500, 1), ('cards', 100, 400, 1000, 2), ('consoles', 1, 5, 14, 3),
         ('legend', 1, 10, 50, 4), ('fullart', 1, 10, 30, 5), ('fuse', 5, 25, 100, 6),
         ('wins', 10, 50, 200, 7), ('gifts', 10, 50, 200, 8), ('sales', 5, 25, 100, 9),
         ('trades', 5, 25, 100, 10), ('gamedle', 10, 50, 200, 11), ('chest', 1, 5, 20, 12),
         ('sagas', 1, 2, 4, 13), ('days', 7, 30, 100, 14), ('epics', 10, 50, 200, 15), ('holo', 10, 50, 200, 16),
         ('gold', 5, 25, 100, 17), ('recycle', 50, 250, 1000, 18), ('quiz', 50, 250, 1000, 19), ('played', 20, 100, 400, 20),
         ('defis', 10, 50, 200, 21), ('premium', 5, 25, 100, 22), ('buys', 5, 25, 100, 23), ('firsttry', 1, 5, 20, 24) $function$;

-- rc__tn
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
                     else coalesce(c.n, 0) end,
         coalesce(g.tier, 0), array[k.t1, k.t2, k.t3], k.ord
    from public.rc__tpool() k
    join public.rc_players p on p.device = p_dev
    left join public.rc_trophy_n c on c.device = p_dev and c.kind = k.kind
    left join public.rc_trophy_got g on g.device = p_dev and g.kind = k.kind $function$;

-- rc__tshow_k
create or replace function public.rc__tshow_k(p_dev text)
 returns text[]
 language plpgsql
 stable security definer
 set search_path to 'public'
as $function$
-- les 3 trophées affichés : ceux choisis (débloqués), et les cases vides remplies par les meilleurs paliers
declare a text[]; r text[] := array['', '', '']; i int; k text;
begin
  select string_to_array(coalesce(trophies, ''), ',') into a from public.rc_players where device = p_dev;
  for i in 1..3 loop
    if i <= coalesce(array_length(a, 1), 0) and a[i] <> '' and not (a[i] = any(r))
       and exists (select 1 from public.rc_trophy_got g where g.device = p_dev and g.kind = a[i] and g.tier > 0) then
      r[i] := a[i];
    end if;
  end loop;
  for k in select g.kind from public.rc_trophy_got g join public.rc__tpool() p on p.kind = g.kind
            where g.device = p_dev and g.tier > 0 and not (g.kind = any(r)) order by g.tier desc, p.ord loop
    i := array_position(r, '');
    exit when i is null;
    r[i] := k;
  end loop;
  return r;
end $function$;

-- rc__tshow
create or replace function public.rc__tshow(p_dev text)
 returns text
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  -- vitrine de trophées « type:palier » (3 cases), ex. « wins:3,cards:2,gifts:1 »
  select coalesce(string_agg(case when g.tier > 0 then x.k || ':' || g.tier else '' end, ',' order by x.o), '')
    from unnest(public.rc__tshow_k(p_dev)) with ordinality x(k, o)
    left join public.rc_trophy_got g on g.device = p_dev and g.kind = x.k $function$;

-- rc__tro_json
create or replace function public.rc__tro_json(p_dev text)
 returns jsonb
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select jsonb_build_object(
    'list', coalesce((select jsonb_agg(jsonb_build_object('k', x.kind, 'n', x.n, 'got', x.got, 't', x.t) order by x.ord)
                        from public.rc__tn(p_dev) x), '[]'::jsonb),
    'show', array_to_string(public.rc__tshow_k(p_dev), ','),  -- vitrine affichée (choix + meilleurs en complément)
    'pick', coalesce((select trophies from public.rc_players where device = p_dev), ''),
    'ready', (select count(*)::int from public.rc__tn(p_dev) x where x.got < 3 and x.n >= x.t[x.got + 1])) $function$;

-- rc__give
create or replace function public.rc__give(p_dev text, p_card text, p_f integer, p_n integer)
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
begin
  insert into public.rc_owned (device, card, finish, qty) values (p_dev, p_card, p_f, p_n)
  on conflict (device, card, finish) do update set qty = public.rc_owned.qty + excluded.qty;
  -- trophées : épiques, légendaires, brillantes, dorées et Full art obtenues
  perform public.rc__tbump(p_dev, case (select rarity from public.rc_cards where id = p_card) when 3 then 'epics' when 4 then 'legend' end, p_n);
  perform public.rc__tbump(p_dev, case p_f when 1 then 'holo' when 2 then 'gold' when 3 then 'fullart' end, p_n);
end $function$;

-- rc__bump
create or replace function public.rc__bump(p_dev text, p_kind text, p_n integer)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
begin
  if p_kind in ('open', 'trade') then perform public.rc__wbump(p_dev, p_kind, p_n); end if;  -- défis de la semaine
  if p_kind = 'open' then
    perform public.rc__ref_check(p_dev);  -- parrainage
    insert into public.rc_daily (day, packs) values (public.rc__today(), p_n)
    on conflict (day) do update set packs = public.rc_daily.packs + p_n;  -- stats admin
  elsif p_kind = 'recycle' then
    perform public.rc__ev_bump(p_dev, 'recycle', p_n);
    perform public.rc__tbump(p_dev, 'recycle', p_n);  -- trophée : doublons recyclés
  end if;
  return '[]'::jsonb;
end $function$;

-- rc__wbump
create or replace function public.rc__wbump(p_dev text, p_kind text, p_n integer)
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare k text[];
begin
  if p_dev is null or coalesce(p_n, 0) <= 0 then return; end if;
  -- trophées : cadeaux, ventes, duels gagnés, Gamedle (comptés même hors des défis de la semaine)
  perform public.rc__tbump(p_dev, case p_kind when 'gift' then 'gifts' when 'sale' then 'sales' when 'win' then 'wins' when 'gamedle' then 'gamedle'
    when 'quiz' then 'quiz' when 'play' then 'played' when 'premium' then 'premium' end, p_n);
  k := public.rc__wkinds();
  if not (p_kind = any(k)) then return; end if;  -- pas au programme cette semaine
  perform public.rc__wk(p_dev);
  update public.rc_players set w_prog[array_position(k, p_kind)] =
         least(coalesce(w_prog[array_position(k, p_kind)], 0) + p_n, 9999)
   where device = p_dev;
end $function$;

-- rc_week_claim
CREATE OR REPLACE FUNCTION public.rc_week_claim(p_device text, p_i integer, p_sig text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare v public.rc_players; bit int; gain int := 0;
begin
  perform public.rc__check(p_sig, p_device || '|wclaim|' || p_i);
  perform public.rc__wk(p_device);
  select * into v from public.rc_players where device = p_device for update;
  if v.device is null then raise exception 'joueur inconnu'; end if;
  if p_i between 1 and 6 then
    bit := 1 << (p_i - 1);
    if (v.w_claim & bit) <> 0 then raise exception 'déjà récupéré'; end if;
    if v.w_prog[p_i] < (public.rc__wgoals())[p_i] then raise exception 'défi pas terminé'; end if;
    gain := (public.rc__wrewards())[p_i];
    update public.rc_players set w_claim = w_claim | bit, coins = coins + gain where device = p_device;
    perform public.rc__tbump(p_device, 'defis', 1);  -- trophée : défis de la semaine réussis
  elsif p_i = 7 then
    if (v.w_claim & 64) <> 0 then raise exception 'coffre déjà ouvert'; end if;
    if (v.w_claim & 63) <> 63 then raise exception 'coffre fermé'; end if;
    gain := public.rc__cfg('chest_coins', 500)::int;
    update public.rc_players set w_claim = w_claim | 64, coins = coins + gain, pixels = pixels + public.rc__cfg('chest_pixels', 2)::int where device = p_device;
    insert into public.rc_gifts (receiver, giver, giver_name, kind) values (p_device, null, 'Défis de la semaine', 'premium');
    perform public.rc__tbump(p_device, 'chest', 1);  -- trophée : coffres des défis
  else
    raise exception 'défi inconnu';
  end if;
  return public.rc__week_json(p_device) || jsonb_build_object('gain', gain);
end $function$;

-- rc_market_buy
create or replace function public.rc_market_buy(p_device text, p_id bigint, p_sig text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare
  m public.rc_market; v public.rc_players; is_new boolean; ev jsonb := '[]'::jsonb;
begin
  perform public.rc__check(p_sig, p_device || '|buy|' || p_id);
  select * into m from public.rc_market x where x.id = p_id and x.buyer is null for update skip locked;
  if m.id is null then return null; end if;
  if m.seller = p_device then raise exception 'c''est ton lot'; end if;
  perform public.rc__not_blocked(p_device);
  perform public.rc__not_blocked(m.seller);
  select * into v from public.rc_players where device = p_device for update;
  if v.coins < m.price then raise exception 'pas assez de pièces'; end if;
  is_new := not exists (select 1 from public.rc_owned where device = p_device and card = m.card);
  update public.rc_market set buyer = p_device, sold_at = now() where id = m.id;
  update public.rc_players set coins = coins - m.price where device = p_device;
  update public.rc_players set coins = coins + m.price where device = m.seller;
  perform public.rc__give(p_device, m.card, m.finish, 1);
  ev := ev || public.rc__bump(p_device, 'trade', 1) || public.rc__milestones(p_device);
  perform public.rc__bump(m.seller, 'trade', 1);
  perform public.rc__ev_bump(m.seller, 'sales', 1);  -- défi : ventes en Bourse
  perform public.rc__wbump(m.seller, 'sale', 1);
  perform public.rc__tbump(p_device, 'buys', 1);  -- trophée : achats à la Bourse
  if is_new then perform public.rc__wbump(p_device, 'new', 1); end if;
  perform public.rc__rescore(p_device);
  return jsonb_build_object('card', m.card, 'f', m.finish, 'n', is_new,
                            'coins', (select coins from public.rc_players where device = p_device), 'events', ev);
end $function$;

-- rc_gamedle_guess
CREATE OR REPLACE FUNCTION public.rc_gamedle_guess(p_device text, p_card text, p_sig text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  ans text := public.rc__gamedle_card(public.rc__today());
  g public.rc_gamedle;
  ok boolean;
  tries int;
  reward int := 0;
begin
  perform public.rc__check(p_sig, p_device || '|gamedle|' || p_card);
  if not exists (select 1 from public.rc_players where device = p_device) then raise exception 'invalide'; end if;
  if not exists (select 1 from public.rc_cards where id = p_card) then raise exception 'carte inconnue'; end if;
  insert into public.rc_gamedle (device, day) values (p_device, public.rc__today()) on conflict do nothing;
  select * into g from public.rc_gamedle where device = p_device and day = public.rc__today() for update;
  if g.won or coalesce(array_length(g.guesses, 1), 0) >= 6 then raise exception 'gamedle terminé'; end if;
  if p_card = any(g.guesses) then raise exception 'déjà proposé'; end if;
  ok := (select regexp_replace(lower(a.title), '[^a-z0-9]', '', 'g') = regexp_replace(lower(b.title), '[^a-z0-9]', '', 'g')
           from public.rc_cards a, public.rc_cards b where a.id = ans and b.id = p_card);
  update public.rc_gamedle set guesses = guesses || p_card, won = ok
   where device = p_device and day = public.rc__today();
  tries := coalesce(array_length(g.guesses, 1), 0) + 1;
  if ok then
    reward := (array[100, 80, 60, 45, 30, 20])[tries];
    update public.rc_players set coins = coins + reward where device = p_device;
    perform public.rc__feed_add(p_device, 'gamedle', ans, null, null, tries);
    perform public.rc__wbump(p_device, 'gamedle', 1);
    if tries = 1 then perform public.rc__tbump(p_device, 'firsttry', 1); end if;  -- trophée : du premier coup
  end if;
  return public.rc__gamedle_json(p_device) || jsonb_build_object('ok', ok, 'reward', reward, 'answer', case when ok or tries >= 6 then ans end);
end $function$;

-- Reprise de l'historique pour les nouveaux trophées (relançable : ne fait que remonter un compteur)
insert into public.rc_trophy_n (device, kind, n)
select device, kind, n from (
  select o.device, case c.rarity when 3 then 'epics' end as kind, sum(o.qty)::int as n
    from public.rc_owned o join public.rc_cards c on c.id = o.card where c.rarity = 3 and o.qty > 0 group by 1, 2
  union all
  select device, case finish when 1 then 'holo' else 'gold' end, sum(qty)::int from public.rc_owned
   where finish in (1, 2) and qty > 0 group by 1, 2
  union all
  select dev, 'played', count(*)::int from (
    select p1 as dev from public.rc_c4 where status = 'done' and coalesce(paid, true)
    union all select p2 from public.rc_c4 where status = 'done' and coalesce(paid, true)
    union all select p1 from public.rc_bs where status = 'done' and coalesce(paid, true)
    union all select p2 from public.rc_bs where status = 'done' and coalesce(paid, true)) d group by 1
  union all
  select device, 'premium', count(*)::int from public.rc_pack_log where kind = 'premium' group by 1
  union all
  select buyer, 'buys', count(*)::int from public.rc_market where sold_at is not null and buyer is not null group by 1
  union all
  select device, 'firsttry', count(*)::int from public.rc_gamedle where won and coalesce(array_length(guesses, 1), 0) = 1 group by 1
) s
where device in (select device from public.rc_players) and n > 0
on conflict (device, kind) do update set n = greatest(public.rc_trophy_n.n, excluded.n);

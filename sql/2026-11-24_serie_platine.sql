-- 24/11/2026 (version 1.0.54) : serie Platine des consoles.
-- Une console finie a 100 % (palier 100) debloque sa serie Platine : finition 4 des memes cartes,
-- une seule version par carte, groupe a part (comme la full art : une Platine + une normale ne font pas un doublon).
--  * paquets : 10 % de chances par carte de console (hors full art) de sortir en Platine si sa console est debloquee
--    (tirage fait dans rc_open_choice, au moment ou les 6 boosters sont prepares) ; jamais dans la roue, la pioche, etc.
--  * rc__give refuse une Platine a un joueur qui n'a pas debloque sa console (Bourse, echanges, cadeaux admin)
--  * score x4, recyclage x15 (entre doree x10 et full art x30), ne compte pas dans le nombre de cartes
--  * Platine finie a 100 % : 5 000 pieces une fois (palier 200), evenement 'platine_done' ;
--    le palier 100 d'une console renvoie maintenant 'platine': true (deblocage)
--  * trophee 'platine' : series Platine completes, paliers 1 / 5 / 15
-- Relancable. 100 % ASCII (textes accentues en U&'...').

-- contraintes eventuelles sur la finition (0-3) : elargies a 0-4
do $$
declare r record;
begin
  for r in
    select c.conname, c.conrelid::regclass as tbl, pg_get_constraintdef(c.oid) as def
      from pg_constraint c join pg_namespace n on n.oid = c.connamespace
     where n.nspname = 'public' and c.contype = 'c' and pg_get_constraintdef(c.oid) ~* '\mfinish\M'
  loop
    if r.def ~* '^CHECK \(\(*finish ' then
      execute format('alter table %s drop constraint %I', r.tbl, r.conname);
      execute format('alter table %s add constraint %I check (finish between 0 and 4)', r.tbl, r.conname);
      raise notice 'contrainte % (%) : 0-4', r.conname, r.tbl;
    end if;
  end loop;
end $$;

-- groupe d'une finition : 0 = normale / brillante / doree, 3 = full art, 4 = Platine
create or replace function public.rc__fam(f integer)
 returns integer
 language sql
 immutable
as $function$
  select case when coalesce(f, 0) < 3 then 0 else f end $function$;
alter function public.rc__fam(integer) owner to rc_owner;

-- Platine de la console de cette carte debloquee (console finie a 100 %)
create or replace function public.rc__platine_ok(p_dev text, p_card text)
 returns boolean
 language sql
 stable
 set search_path to 'public'
as $function$
  select exists (select 1 from public.rc_cards c join public.rc_milestones m on m.sys = c.sys
                  where c.id = p_card and c.saga is null and m.device = p_dev and m.step = 100) $function$;
alter function public.rc__platine_ok(text, text) owner to rc_owner;

-- 10 % de chances par carte de console (hors full art) de passer en Platine, consoles debloquees seulement
create or replace function public.rc__platine_mark(p_dev text, p_packs jsonb)
 returns jsonb
 language plpgsql
 set search_path to 'public'
as $function$
declare unl text[]; out jsonb := '[]'::jsonb; pk jsonb; e jsonb; one jsonb;
begin
  select array_agg(m.sys) into unl from public.rc_milestones m where m.device = p_dev and m.step = 100;
  if unl is null then return p_packs; end if;
  for pk in select * from jsonb_array_elements(p_packs) loop
    one := '[]'::jsonb;
    for e in select * from jsonb_array_elements(pk) loop
      if coalesce((e->>'f')::int, 0) < 3 and random() < 0.10
         and exists (select 1 from public.rc_cards c where c.id = e->>'c' and c.saga is null and c.sys = any(unl)) then
        e := jsonb_set(e, '{f}', '4'::jsonb);
      end if;
      one := one || jsonb_build_array(e);
    end loop;
    out := out || jsonb_build_array(one);
  end loop;
  return out;
end $function$;
alter function public.rc__platine_mark(text, jsonb) owner to rc_owner;

create or replace function public.rc__give(p_dev text, p_card text, p_f integer, p_n integer)
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
begin
  if p_f = 4 and not public.rc__platine_ok(p_dev, p_card) then raise exception 'platine verrouillee'; end if;
  insert into public.rc_owned (device, card, finish, qty) values (p_dev, p_card, p_f, p_n)
  on conflict (device, card, finish) do update set qty = public.rc_owned.qty + excluded.qty;
  -- trophees : epiques, legendaires, brillantes, dorees et Full art obtenues
  perform public.rc__tbump(p_dev, case (select rarity from public.rc_cards where id = p_card) when 3 then 'epics' when 4 then 'legend' end, p_n);
  perform public.rc__tbump(p_dev, case p_f when 1 then 'holo' when 2 then 'gold' when 3 then 'fullart' end, p_n);
end $function$;

create or replace function public.rc__is_new(p_device text, p_card text, p_finish int)
 returns boolean
 language sql
 stable
 set search_path to 'public'
as $function$
  select not exists (select 1 from public.rc_owned
                      where device = p_device and card = p_card and qty > 0
                        and public.rc__fam(finish) = public.rc__fam(p_finish))
$function$;

CREATE OR REPLACE FUNCTION public.rc__recycle_value(r integer, f integer)
 RETURNS integer
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select (array[2, 5, 20, 60, 200])[r + 1] * (array[1, 3, 10, 30, 15])[least(greatest(f, 0), 4) + 1] $function$;

create or replace function public.rc_recycle(p_device text, p_card text, p_finish integer, p_qty integer, p_sig text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare
  total int; r int; gain int; ev jsonb := '[]'::jsonb;
begin
  perform public.rc__check(p_sig, p_device || '|recycle|' || p_card || '|' || p_finish || '|' || p_qty);
  if p_qty < 1 then raise exception '%', U&'quantit\00E9 invalide'; end if;
  perform 1 from public.rc_players where device = p_device for update;
  -- le full art est une carte a part : on garde 1 exemplaire normal / brillant / dore ET 1 full art
  select coalesce(sum(qty), 0) into total from public.rc_owned
   where device = p_device and card = p_card and public.rc__fam(finish) = public.rc__fam(p_finish);
  if total - p_qty < 1 then raise exception 'dernier exemplaire'; end if;
  if not public.rc__take(p_device, p_card, p_finish, p_qty) then raise exception 'pas assez d''exemplaires'; end if;
  select rarity into r from public.rc_cards where id = p_card;
  gain := public.rc__recycle_value(r, p_finish) * p_qty * least(coalesce(public.rc__effect('recycle_x'), 1), 5);
  update public.rc_players set fragments = fragments + gain where device = p_device;
  ev := public.rc__bump(p_device, 'recycle', p_qty);
  perform public.rc__rescore(p_device);
  return jsonb_build_object('gain', gain, 'fragments', (select fragments from public.rc_players where device = p_device), 'events', ev);
end $function$;

CREATE OR REPLACE FUNCTION public.rc_market_groups(p_device text, p_sys text, p_missing boolean)
 RETURNS TABLE(card text, finish smallint, lots integer, min_price integer, last_at timestamp with time zone, seller text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select m.card, m.finish, count(*)::int, min(m.price)::int, max(m.created_at),
         (select p.name from public.rc_market m2 join public.rc_players p on p.device = m2.seller
           where m2.card = m.card and m2.finish = m.finish and m2.buyer is null and m2.seller <> p_device
           order by m2.price, m2.created_at limit 1)
    from public.rc_market m
    join public.rc_cards c on c.id = m.card
   where m.buyer is null and m.seller <> p_device
     and (p_sys is null or p_sys = '' or c.sys = p_sys)
     and (not coalesce(p_missing, false)
          or not exists (select 1 from public.rc_owned o where o.device = p_device and o.card = m.card and o.qty > 0
                            and public.rc__fam(o.finish) = public.rc__fam(m.finish)))  -- full art = carte a part
   group by m.card, m.finish
   order by max(m.created_at) desc
   limit 300 $function$;

-- Mes cartes manquantes que les voisins ont en double (vus depuis 30 jours) : un bloc par joueur,
-- du joueur qui en a le plus au moins ; cartes de la plus rare a la plus commune. Relancable.
create or replace function public.rc_missing_finder(p_device text, p_sig text)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to 'public'
as $function$
begin
  perform public.rc__check(p_sig, p_device || '|missing');
  return (
    with mine as (
      select distinct card from public.rc_owned where device = p_device and qty > 0 and finish < 3  -- full art = carte a part
    ), dbl as (
      select o.device, o.card, sum(o.qty)::int as q
        from public.rc_owned o
       where o.device <> p_device and o.finish < 3 and not exists (select 1 from mine m where m.card = o.card)
       group by o.device, o.card
      having sum(o.qty) >= 2
    ), per as (
      select p.pid, p.name, p.avatar, (p.seen_at > now() - interval '75 seconds') as online, count(*)::int as n,
             jsonb_agg(jsonb_build_array(d.card, d.q) order by c.rarity desc, d.card) as cards
        from dbl d
        join public.rc_players p on p.device = d.device
        join public.rc_cards c on c.id = d.card
       where p.seen_at > now() - interval '30 days'
       group by p.pid, p.name, p.avatar, p.seen_at
       order by count(*) desc, p.seen_at desc
       limit 40
    )
    select jsonb_build_object(
             'cards', (select count(distinct d.card) from dbl d join public.rc_players p on p.device = d.device
                        where p.seen_at > now() - interval '30 days'),
             'players', coalesce((select jsonb_agg(to_jsonb(per) order by per.n desc) from per), '[]'::jsonb))
  );
end $function$;

CREATE OR REPLACE FUNCTION public.rc__rescore(p_dev text)
 RETURNS void
 LANGUAGE sql
AS $function$
  update public.rc_players p set
    cards = (select count(distinct o.card) filter (where o.finish < 3) + count(distinct o.card) filter (where o.finish = 3)
               from public.rc_owned o where o.device = p_dev and o.qty > 0),  -- une full art = une carte de plus (onglet a part)
    score = coalesce((select sum(public.rc__pts(c.rarity) * (case o.finish when 0 then 1 when 1 then 1 when 2 then 3 when 4 then 4 else 6 end))
                        from public.rc_owned o join public.rc_cards c on c.id = o.card
                       where o.device = p_dev), 0),
    updated_at = now()
  where p.device = p_dev $function$;

CREATE OR REPLACE FUNCTION public.rc__milestones(p_dev text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
declare
  rec record; s int; ev jsonb := '[]'::jsonb; reward int;
begin
  for rec in
    select c.sys, count(*) as total, count(o.card) as mine, max(so.n) as old_n, bool_and(c.saga is null) as console,
           count(pl.card) as plat
      from public.rc_cards c
      left join (select distinct card from public.rc_owned where device = p_dev and qty > 0 and finish < 3) o on o.card = c.id  -- full art : onglet a part
      left join (select distinct card from public.rc_owned where device = p_dev and qty > 0 and finish = 4) pl on pl.card = c.id
      left join public.rc_sys_old so on so.sys = c.sys
     group by c.sys
  loop
    -- ancienne serie complete (console agrandie le 15/11) : 2000 pieces une fois, palier 99
    if rec.old_n is not null and rec.old_n < rec.total and rec.mine >= rec.old_n then
      insert into public.rc_milestones (device, sys, step) values (p_dev, rec.sys, 99) on conflict do nothing;
      if found then
        update public.rc_players set coins = coins + 2000 where device = p_dev;
        ev := ev || jsonb_build_object('type', 'milestone', 'sys', rec.sys, 'step', round(rec.old_n * 100.0 / rec.total)::int,
                                       'coins', 2000, 'old', rec.old_n);
      end if;
    end if;
    foreach s in array case when rec.sys like 'sg\_%' then array[50, 100] else array[25, 50, 75, 100] end loop
      if rec.mine * 100 >= rec.total * s then
        insert into public.rc_milestones (device, sys, step) values (p_dev, rec.sys, s) on conflict do nothing;
        if found then
          if rec.sys like 'sg\_%' then
            reward := case s when 50 then 100 else 500 end;
            update public.rc_players set coins = coins + reward, pixels = pixels + case when s = 100 then 2 else 0 end where device = p_dev;
          else
            reward := case s when 25 then 100 when 50 then 250 when 75 then 500 else 2000 end;
            update public.rc_players set coins = coins + reward where device = p_dev;
          end if;
          ev := ev || (jsonb_build_object('type', 'milestone', 'sys', rec.sys, 'step', s, 'coins', reward)
                       || case when s = 100 and rec.console then jsonb_build_object('platine', true) else '{}'::jsonb end);
        end if;
      end if;
    end loop;
    -- serie Platine finie : 5 000 pieces une fois (palier 200)
    if rec.console and rec.plat >= rec.total
       and exists (select 1 from public.rc_milestones m where m.device = p_dev and m.sys = rec.sys and m.step = 100) then
      insert into public.rc_milestones (device, sys, step) values (p_dev, rec.sys, 200) on conflict do nothing;
      if found then
        update public.rc_players set coins = coins + 5000 where device = p_dev;
        ev := ev || jsonb_build_object('type', 'platine_done', 'sys', rec.sys, 'coins', 5000);
      end if;
    end if;
  end loop;
  return ev;
end $function$;

CREATE OR REPLACE FUNCTION public.rc_open_choice(p_device text, p_kind text, p_sys text, p_sig text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  v public.rc_players;
  pd public.rc_pending;
  price int := public.rc__pack_price(p_kind);
  sp int := public.rc__special_cost(p_kind);
  packs jsonb := '[]'::jsonb; gid bigint; i int; gk text;
begin
  perform public.rc__check(p_sig, p_device || '|open6|' || coalesce(p_kind, '') || '|' || coalesce(p_sys, ''));
  select * into v from public.rc_players where device = p_device for update;
  if v.device is null then raise exception 'joueur inconnu'; end if;

  select * into pd from public.rc_pending where device = p_device;
  if pd.device is not null then
    return jsonb_build_object('choose', jsonb_array_length(pd.packs), 'kind', pd.kind, 'sys', pd.sys, 'gk', pd.gk, 'resumed', true,
                              'coins', v.coins, 'lots', v.lots, 'pixels', v.pixels,
                              'gifts', (select count(*)::int from public.rc_gifts g where g.receiver = p_device and g.opened_at is null));
  end if;

  if price is null and sp is null then raise exception 'paquet inconnu'; end if;
  if p_kind in ('console', 'sconsole') and not exists (select 1 from public.rc_cards where sys = p_sys) then
    raise exception 'console inconnue';
  end if;
  if sp is not null then
    -- booster special : paye en pixels
    if v.pixels < sp then raise exception 'pas assez de pixels'; end if;
    update public.rc_players set pixels = pixels - sp where device = p_device;
  elsif p_kind = 'free' then
    if public.rc__free_in(p_device) > 0 then raise exception '%', U&'paquet gratuit pas encore pr\00EAt'; end if;
    update public.rc_players set last_free = public.rc__today(), last_free_at = now() where device = p_device;
  elsif p_kind = 'gift' then
    select g.id, g.kind into gid, gk from public.rc_gifts g
     where g.receiver = p_device and g.opened_at is null
       and (coalesce(p_sys, '') = '' or g.id::text = p_sys)
     order by g.id limit 1 for update;
    if gid is null then raise exception 'aucun cadeau'; end if;
    update public.rc_gifts set opened_at = now() where id = gid;
  elsif p_kind = 'lot' then
    if v.lots < 1 then raise exception 'aucun paquet du lot'; end if;
    update public.rc_players set lots = lots - 1 where device = p_device;
  elsif v.coins < price then
    raise exception '%', U&'pas assez de pi\00E8ces';
  else
    update public.rc_players set coins = coins - price where device = p_device;
  end if;

  for i in 1..6 loop
    packs := packs || jsonb_build_array(public.rc__draw_pack(case when p_kind = 'gift' then coalesce(gk, 'gift') else p_kind end, p_sys, v.pity));
  end loop;
  packs := public.rc__platine_mark(p_device, packs);  -- Platine : 10 % par carte des consoles debloquees
  insert into public.rc_pending (device, kind, sys, packs, gk) values (p_device, p_kind, p_sys, packs, gk);

  select * into v from public.rc_players where device = p_device;
  return jsonb_build_object('choose', 6, 'kind', p_kind, 'sys', p_sys, 'gk', gk, 'resumed', false,
                            'coins', v.coins, 'lots', v.lots, 'pixels', v.pixels,
                            'gifts', (select count(*)::int from public.rc_gifts g where g.receiver = p_device and g.opened_at is null));
end $function$;

create or replace function public.rc__tpool()
 returns table(kind text, t1 integer, t2 integer, t3 integer, ord integer)
 language sql
 immutable
as $function$
  -- trophees a 3 paliers (bronze, argent, or) ; textes et icones dans lib/trophies.dart
  values ('packs', 25, 100, 500, 1), ('cards', 100, 400, 1000, 2), ('consoles', 1, 5, 29, 3),
         ('legend', 1, 10, 50, 4), ('fullart', 1, 10, 30, 5), ('fuse', 5, 25, 100, 6),
         ('wins', 10, 50, 200, 7), ('gifts', 10, 50, 200, 8), ('sales', 5, 25, 100, 9),
         ('trades', 5, 25, 100, 10), ('gamedle', 10, 50, 200, 11), ('chest', 1, 5, 20, 12),
         ('sagas', 1, 3, 12, 13), ('days', 7, 30, 100, 14), ('epics', 10, 50, 200, 15), ('holo', 10, 50, 200, 16),
         ('gold', 5, 25, 100, 17), ('recycle', 50, 250, 1000, 18), ('quiz', 50, 250, 1000, 19), ('played', 20, 100, 400, 20),
         ('defis', 10, 50, 200, 21), ('premium', 5, 25, 100, 22), ('buys', 5, 25, 100, 23), ('firsttry', 1, 5, 20, 24),
         ('tourney', 1, 3, 10, 25), ('pioche', 5, 30, 100, 26), ('express', 5, 30, 100, 27),
         ('wheel', 10, 50, 200, 28), ('pokemon', 10, 50, 185, 29),
         ('react', 10, 50, 200, 30), ('craft', 5, 25, 100, 31), ('sagacards', 25, 75, 156, 32),
         -- ajoutes le 7/11
         ('cartoon', 10, 40, 80, 33), ('dragonball', 50, 200, 556, 34), ('dbholo', 10, 50, 146, 35),
         ('sunday', 1, 4, 12, 36), ('podium', 1, 5, 20, 37), ('score', 1000, 5000, 15000, 38),
         ('boosters', 5, 25, 100, 39),
         -- ajoute le 24/11
         ('platine', 1, 5, 15, 40) $function$;

CREATE OR REPLACE FUNCTION public.rc__tn(p_dev text)
 RETURNS TABLE(kind text, n integer, got integer, t integer[], ord integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- progression de chaque trophee : paquets, cartes et consoles lus en direct, le reste compte
  select k.kind,
         case k.kind when 'packs' then p.packs
                     when 'cards' then p.cards
                     when 'consoles' then (select count(distinct m.sys)::int from public.rc_milestones m
                                            where m.device = p_dev and m.step in (99, 100) and m.sys not like 'sg\_%')
                     when 'sagas' then (select count(*)::int from public.rc_milestones m
                                         where m.device = p_dev and m.step = 100 and m.sys like 'sg\_%')
                     when 'days' then p.days
                     when 'react' then (select count(*)::int from public.rc_feed_react r where r.device = p_dev)
                     when 'sagacards' then (select count(*)::int from public.rc_owned o join public.rc_cards cc on cc.id = o.card
                                             where o.device = p_dev and o.qty > 0 and cc.saga is not null and cc.saga not in ('pk', 'da', 'db'))
                     when 'pokemon' then (select count(*)::int from public.rc_owned o join public.rc_cards cc on cc.id = o.card
                                           where o.device = p_dev and o.qty > 0 and cc.saga = 'pk')
                     when 'cartoon' then (select count(distinct o.card)::int from public.rc_owned o join public.rc_cards cc on cc.id = o.card
                                           where o.device = p_dev and o.qty > 0 and cc.saga = 'da')
                     when 'dragonball' then (select count(distinct o.card)::int from public.rc_owned o join public.rc_cards cc on cc.id = o.card
                                              where o.device = p_dev and o.qty > 0 and cc.saga = 'db')
                     when 'dbholo' then (select count(distinct o.card)::int from public.rc_owned o join public.rc_cards cc on cc.id = o.card
                                          where o.device = p_dev and o.qty > 0 and cc.saga = 'db' and cc.rarity >= 4)
                     when 'podium' then (select count(*)::int from public.rc_rj_wins w where w.device = p_dev)
                                      + (select count(*)::int from public.rc_rn_wins w where w.device = p_dev)
                     when 'platine' then (select count(*)::int from public.rc_milestones m
                                           where m.device = p_dev and m.step = 200)
                     when 'score' then p.score
                     when 'boosters' then (select count(*)::int from public.rc_pack_log l
                                            where l.device = p_dev and l.kind in ('pokemon', 'cartoon', 'dragonball'))
                     else coalesce(c.n, 0) end,
         coalesce(g.tier, 0), array[k.t1, k.t2, k.t3], k.ord
    from public.rc__tpool() k
    join public.rc_players p on p.device = p_dev
    left join public.rc_trophy_n c on c.device = p_dev and c.kind = k.kind
    left join public.rc_trophy_got g on g.device = p_dev and g.kind = k.kind $function$;

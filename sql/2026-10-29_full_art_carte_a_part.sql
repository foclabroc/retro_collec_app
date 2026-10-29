-- 29/10/2026 : le full art compte comme une carte à part.
-- Une normale (ou brillante / dorée) et une full art de la même carte ne font pas un doublon :
-- « Nouvelle ! » si on n'a pas encore ce groupe (normal/brillant/doré, ou full art),
-- recyclage : on garde toujours 1 exemplaire de chaque groupe ; cartes manquantes : par groupe.
-- Les full art ne comptent plus dans les consoles (seulement dans l'onglet Full art) : paliers de console,
-- nombre de cartes (Voisinage, trophée Cartes), Bourse « manquantes ». Paliers déjà gagnés : gardés.
-- Relançable.

create or replace function public.rc__is_new(p_device text, p_card text, p_finish int)
 returns boolean
 language sql
 stable
 set search_path to 'public'
as $function$
  select not exists (select 1 from public.rc_owned
                      where device = p_device and card = p_card and qty > 0
                        and (finish = 3) = (coalesce(p_finish, 0) = 3))
$function$;
alter function public.rc__is_new(text, text, int) owner to rc_owner;

-- rc_open
CREATE OR REPLACE FUNCTION public.rc_open(p_device text, p_kind text, p_sys text, p_sig text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  v public.rc_players;
  price int := public.rc__pack_price(p_kind);
  scope text := case when p_kind = 'console' then p_sys else null end;
  n int := 5; x float;
  i int; r int; f int; c text; sg text; is_new boolean; got_epic boolean := false; nnew int := 0;
  res jsonb := '[]'::jsonb; ev jsonb := '[]'::jsonb; gid bigint;
begin
  perform public.rc__check(p_sig, p_device || '|open|' || coalesce(p_kind, '') || '|' || coalesce(p_sys, ''));
  if price is null then raise exception 'paquet inconnu'; end if;
  if p_kind = 'console' and not exists (select 1 from public.rc_cards where sys = p_sys) then
    raise exception 'console inconnue';
  end if;
  select * into v from public.rc_players where device = p_device for update;
  if v.device is null then raise exception 'joueur inconnu'; end if;
  if p_kind = 'free' then
    if public.rc__free_in(p_device) > 0 then raise exception 'paquet gratuit pas encore prêt'; end if;
    update public.rc_players set last_free = public.rc__today(), last_free_at = now() where device = p_device;
  elsif p_kind = 'gift' then
    -- un cadeau précis (p_sys = son numéro) ou le plus ancien
    select g.id into gid from public.rc_gifts g
     where g.receiver = p_device and g.opened_at is null
       and (coalesce(p_sys, '') = '' or g.id::text = p_sys)
     order by g.id limit 1 for update;
    if gid is null then raise exception 'aucun cadeau'; end if;
    update public.rc_gifts set opened_at = now() where id = gid;
  elsif p_kind = 'lot' then
    if v.lots < 1 then raise exception 'aucun paquet du lot'; end if;
    update public.rc_players set lots = lots - 1 where device = p_device;
  elsif v.coins < price then
    raise exception 'pas assez de pièces';
  else
    update public.rc_players set coins = coins - price where device = p_device;
  end if;

  if p_kind = 'mystery' then
    x := random();
    n := case when x < 0.5 then 3 when x < 0.9 then 5 else 8 end;
  end if;

  for i in 1..n loop
    if i = n and p_kind = 'premium' then r := public.rc__roll(2); else r := public.rc__roll(0); end if;
    if i = n and not got_epic and v.pity >= 29 then r := public.rc__roll(3); end if;
    select id into c from public.rc_cards
     where rarity = r and saga is null and (scope is null or sys = scope) order by random() limit 1;
    if c is null then
      select id, rarity into c, r from public.rc_cards
       where rarity <= r and saga is null and (scope is null or sys = scope) order by rarity desc, random() limit 1;
    end if;
    if c is null then raise exception 'catalogue vide'; end if;
    if r >= 3 then got_epic := true; end if;
    f := public.rc__roll_finish(r);
    sg := public.rc__saga_roll();  -- carte de saga
    if sg is not null then c := sg; r := 3; f := 0; got_epic := true; end if;
    is_new := public.rc__is_new(p_device, c, f);
    if is_new then nnew := nnew + 1; end if;
    perform public.rc__give(p_device, c, f, 1);
    res := res || jsonb_build_object('c', c, 'f', f, 'r', r, 'n', is_new);
    c := null;
  end loop;

  update public.rc_players set packs = packs + 1, pity = case when got_epic then 0 else pity + 1 end,
         pixels = pixels + 1
   where device = p_device;
  ev := ev || public.rc__bump(p_device, 'open', 1);
  if got_epic then  -- défi : carte épique ou mieux
    perform public.rc__wbump(p_device, 'epic', 1);
    perform public.rc__ev_bump(p_device, 'epics', 1);
  end if;
  perform public.rc__wbump(p_device, 'new', nnew);  -- défi : nouvelles cartes
  if p_kind in ('free', 'premium') then perform public.rc__wbump(p_device, p_kind, 1); end if;  -- défis : paquet gratuit, premium
  ev := ev || public.rc__milestones(p_device);
  perform public.rc__rescore(p_device);
  select * into v from public.rc_players where device = p_device;
  return jsonb_build_object('cards', res, 'coins', v.coins, 'pity', v.pity, 'score', v.score, 'events', ev,
                            'lots', v.lots, 'pixels', v.pixels,
                            'gifts', (select count(*)::int from public.rc_gifts g where g.receiver = p_device and g.opened_at is null));
end $function$;

-- rc_pick
create or replace function public.rc_pick(p_device text, p_choice integer, p_sig text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare
  v public.rc_players;
  pd public.rc_pending;
  kk text; e jsonb; c text; f int; r int; is_new boolean; got_epic boolean := false; nnew int := 0; s text;
  res jsonb := '[]'::jsonb; ev jsonb := '[]'::jsonb; miss jsonb; miss_b int;
begin
  perform public.rc__check(p_sig, p_device || '|pick|' || p_choice);
  select * into v from public.rc_players where device = p_device for update;
  if v.device is null then raise exception 'joueur inconnu'; end if;
  select * into pd from public.rc_pending where device = p_device for update;
  if pd.device is null then raise exception 'aucun booster à choisir'; end if;
  if p_choice is null or p_choice < 0 or p_choice >= jsonb_array_length(pd.packs) then
    raise exception 'booster inconnu';
  end if;

  for e in select * from jsonb_array_elements(pd.packs -> p_choice) loop
    c := e ->> 'c'; f := (e ->> 'f')::int; r := (e ->> 'r')::int;
    if r >= 3 then got_epic := true; end if;
    is_new := public.rc__is_new(p_device, c, f);
    if is_new then nnew := nnew + 1; end if;
    perform public.rc__give(p_device, c, f, 1);
    res := res || jsonb_build_object('c', c, 'f', f, 'r', r, 'n', is_new);
    select sys into s from public.rc_cards where id = c;
    perform public.rc__ev_bump(p_device, 'console', 1, s);  -- défi : cartes d'une console
  end loop;

  -- la meilleure carte des 5 autres boosters
  select x.card, (x.ord - 1)::int into miss, miss_b
    from (select p.ord, k.card from jsonb_array_elements(pd.packs) with ordinality p(pack, ord),
                 jsonb_array_elements(p.pack) k(card)) x
   where x.ord - 1 <> p_choice
   order by (x.card ->> 'r')::int * 3 + (x.card ->> 'f')::int desc, random()
   limit 1;
  if miss is not null then
    miss := miss || jsonb_build_object('b', miss_b,
      'n', not exists (select 1 from public.rc_owned where device = p_device and card = miss ->> 'c'));
  end if;

  delete from public.rc_pending where device = p_device;
  kk := case when pd.kind = 'gift' then pd.gk else pd.kind end;  -- type réel (un cadeau peut être un premium)
  insert into public.rc_pack_log (device, kind, sys) values (p_device, pd.kind, pd.sys);  -- stats admin
  update public.rc_players set packs = packs + 1, pity = case when got_epic then 0 else pity + 1 end,
         pixels = pixels + case when public.rc__special_cost(pd.kind) is null then 1 else 0 end
   where device = p_device;
  ev := ev || public.rc__bump(p_device, 'open', 1);
  if kk in ('free', 'premium') then perform public.rc__wbump(p_device, kk, 1); end if;  -- défis + trophée : paquet gratuit, premium
  if got_epic then  -- défi : carte épique ou mieux
    perform public.rc__wbump(p_device, 'epic', 1);
    perform public.rc__ev_bump(p_device, 'epics', 1);
  end if;
  perform public.rc__wbump(p_device, 'new', nnew);  -- défi : nouvelles cartes
  ev := ev || public.rc__milestones(p_device);
  perform public.rc__rescore(p_device);
  select * into v from public.rc_players where device = p_device;
  return jsonb_build_object('cards', res, 'choice', p_choice, 'missed', miss, 'kind', pd.kind, 'sys', pd.sys,
                            'coins', v.coins, 'pity', v.pity, 'pixels', v.pixels,
                            'pixel_gain', case when public.rc__special_cost(pd.kind) is null then 1 else 0 end, 'score', v.score, 'events', ev, 'lots', v.lots,
                            'gifts', (select count(*)::int from public.rc_gifts g where g.receiver = p_device and g.opened_at is null));
end $function$;

-- rc_wheel
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
  r int; f int; c text; is_new boolean; card jsonb := null; ev jsonb := '[]'::jsonb;
  minr int;
begin
  perform public.rc__check(p_sig, p_device || '|wheel');
  select * into v from public.rc_players where device = p_device for update;
  if v.device is null then raise exception 'joueur inconnu'; end if;
  if v.wheel_day = public.rc__today() then raise exception 'déjà tourné aujourd''hui'; end if;
  gold := v.streak > 0 and v.streak % 7 = 0 and v.last_login = public.rc__today();
  if gold then
    w := array[20, 16, 14, 18, 10, 13, 6, 3];
    prize := array[40, 100, 0, 60, 200, 80, 0, 1000];
  else
    w := array[22, 16, 12, 20, 8, 15, 4, 3];
    prize := array[20, 50, 0, 30, 100, 40, 0, 300];
  end if;
  for k in 1..8 loop
    acc := acc + w[k];
    if x < acc then seg := k - 1; exit; end if;
  end loop;
  update public.rc_players set wheel_day = public.rc__today(), coins = coins + prize[seg + 1] where device = p_device;
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
  end if;
  return jsonb_build_object('seg', seg, 'gain', prize[seg + 1], 'card', card, 'events', ev, 'gold', gold,
                            'coins', (select p.coins from public.rc_players p where p.device = p_device));
end $function$;

-- rc_craft
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
  perform public.rc__give(p_device, p_card, 0, 1);
  ev := public.rc__milestones(p_device);
  perform public.rc__rescore(p_device);
  return jsonb_build_object('n', is_new, 'coins', (select coins from public.rc_players where device = p_device), 'events', ev);
end $function$;

-- rc_stock_take
create or replace function public.rc_stock_take(p_device text, p_id bigint, p_sig text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare
  v public.rc_players; s public.rc_card_stock; r int; sy text; is_new boolean; nnew int := 0;
  res jsonb := '[]'::jsonb; ev jsonb := '[]'::jsonb;
begin
  perform public.rc__check(p_sig, p_device || '|stocktake|' || coalesce(p_id, 0));
  select * into v from public.rc_players where device = p_device for update;
  if v.device is null then raise exception 'joueur inconnu'; end if;
  for s in select * from public.rc_card_stock
            where device = p_device and taken_at is null and (p_id is null or id = p_id)
            order by id for update loop
    select rarity, sys into r, sy from public.rc_cards where id = s.card;
    is_new := public.rc__is_new(p_device, s.card, s.finish);
    if is_new then nnew := nnew + 1; end if;
    perform public.rc__give(p_device, s.card, s.finish, 1);
    update public.rc_card_stock set taken_at = now() where id = s.id;
    res := res || jsonb_build_object('c', s.card, 'f', s.finish, 'r', r, 'n', is_new);
    perform public.rc__ev_bump(p_device, 'console', 1, sy);  -- défi : cartes d'une console
  end loop;
  if jsonb_array_length(res) = 0 then raise exception 'rien à ranger'; end if;
  perform public.rc__wbump(p_device, 'new', nnew);  -- défi : nouvelles cartes
  ev := ev || public.rc__milestones(p_device);
  perform public.rc__rescore(p_device);
  select * into v from public.rc_players where device = p_device;
  return jsonb_build_object('cards', res, 'events', ev, 'coins', v.coins, 'pixels', v.pixels, 'score', v.score,
                            'left', (select count(*)::int from public.rc_card_stock x where x.device = p_device and x.taken_at is null));
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
  perform public.rc__not_new(p_device);
  select * into m from public.rc_market x where x.id = p_id and x.buyer is null for update skip locked;
  if m.id is null then return null; end if;
  if m.seller = p_device then raise exception 'c''est ton lot'; end if;
  perform public.rc__not_blocked(p_device);
  perform public.rc__not_blocked(m.seller);
  select * into v from public.rc_players where device = p_device for update;
  if v.coins < m.price then raise exception 'pas assez de pièces'; end if;
  is_new := public.rc__is_new(p_device, m.card, m.finish);
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

-- rc__market_buy1
create or replace function public.rc__market_buy1(p_device text, p_id bigint)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare
  m public.rc_market; v public.rc_players; is_new boolean; ev jsonb := '[]'::jsonb;
begin
  select * into m from public.rc_market x where x.id = p_id and x.buyer is null for update skip locked;
  if m.id is null then return null; end if;
  if m.seller = p_device then raise exception 'c''est ton lot'; end if;
  perform public.rc__not_blocked(m.seller);
  select * into v from public.rc_players where device = p_device for update;
  if v.coins < m.price then raise exception 'pas assez de pièces'; end if;
  is_new := public.rc__is_new(p_device, m.card, m.finish);
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
  return jsonb_build_object('card', m.card, 'f', m.finish, 'n', is_new, 'price', m.price, 'events', ev);
end $function$;

-- rc_recycle
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
  if p_qty < 1 then raise exception 'quantité invalide'; end if;
  perform 1 from public.rc_players where device = p_device for update;
  -- le full art est une carte à part : on garde 1 exemplaire normal / brillant / doré ET 1 full art
  select coalesce(sum(qty), 0) into total from public.rc_owned
   where device = p_device and card = p_card and (finish = 3) = (p_finish = 3);
  if total - p_qty < 1 then raise exception 'dernier exemplaire'; end if;
  if not public.rc__take(p_device, p_card, p_finish, p_qty) then raise exception 'pas assez d''exemplaires'; end if;
  select rarity into r from public.rc_cards where id = p_card;
  gain := public.rc__recycle_value(r, p_finish) * p_qty * least(coalesce(public.rc__effect('recycle_x'), 1), 5);
  update public.rc_players set coins = coins + gain where device = p_device;
  ev := public.rc__bump(p_device, 'recycle', p_qty);
  perform public.rc__rescore(p_device);
  return jsonb_build_object('gain', gain, 'coins', (select coins from public.rc_players where device = p_device), 'events', ev);
end $function$;

-- rc_missing_finder
-- Mes cartes manquantes que les voisins ont en double (vus depuis 30 jours) : un bloc par joueur,
-- du joueur qui en a le plus au moins ; cartes de la plus rare à la plus commune. Relançable.
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
      select distinct card from public.rc_owned where device = p_device and qty > 0 and finish <> 3  -- full art = carte à part
    ), dbl as (
      select o.device, o.card, sum(o.qty)::int as q
        from public.rc_owned o
       where o.device <> p_device and o.finish <> 3 and not exists (select 1 from mine m where m.card = o.card)
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

-- rc__milestones
CREATE OR REPLACE FUNCTION public.rc__milestones(p_dev text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
declare
  rec record; s int; ev jsonb := '[]'::jsonb; reward int;
begin
  for rec in
    select c.sys, count(*) as total, count(o.card) as mine
      from public.rc_cards c
      left join (select distinct card from public.rc_owned where device = p_dev and qty > 0 and finish <> 3) o on o.card = c.id  -- full art : onglet à part
     group by c.sys
  loop
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
          ev := ev || jsonb_build_object('type', 'milestone', 'sys', rec.sys, 'step', s, 'coins', reward);
        end if;
      end if;
    end loop;
  end loop;
  return ev;
end $function$;

-- rc__rescore
CREATE OR REPLACE FUNCTION public.rc__rescore(p_dev text)
 RETURNS void
 LANGUAGE sql
AS $function$
  update public.rc_players p set
    cards = (select count(distinct o.card) from public.rc_owned o where o.device = p_dev and o.qty > 0 and o.finish <> 3),  -- full art : onglet à part
    score = coalesce((select sum(public.rc__pts(c.rarity) * (case o.finish when 0 then 1 when 1 then 1 when 2 then 3 else 6 end))
                        from public.rc_owned o join public.rc_cards c on c.id = o.card
                       where o.device = p_dev), 0),
    updated_at = now()
  where p.device = p_dev $function$;

-- rc_market_groups
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
                            and (o.finish = 3) = (m.finish = 3)))  -- full art = carte à part
   group by m.card, m.finish
   order by max(m.created_at) desc
   limit 300 $function$;

-- nombre de cartes recalculé pour tout le monde
do $$ declare d text; begin
  for d in select device from public.rc_players loop perform public.rc__rescore(d); end loop;
end $$;

notify pgrst, 'reload schema';

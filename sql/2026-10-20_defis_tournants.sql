-- Défis de la semaine tournants : 6 défis tirés chaque lundi dans un réservoir de 12 (relançable)
-- La semaine en cours (19/10) garde les 6 défis actuels, la rotation démarre lundi 26/10.

-- rc__wpool
create or replace function public.rc__wpool()
 returns table(id integer, kind text, goal integer, reward integer)
 language sql
 immutable
as $function$
  -- réservoir des défis de la semaine : 6 sont tirés au hasard chaque lundi (ne pas renuméroter)
  values (1, 'open', 10, 150), (2, 'gift', 9, 100), (3, 'trade', 3, 200), (4, 'win', 2, 200),
         (5, 'gamedle', 3, 100), (6, 'epic', 1, 150), (7, 'play', 4, 150), (8, 'new', 15, 150),
         (9, 'quiz', 30, 100), (10, 'sale', 2, 150), (11, 'free', 5, 150), (12, 'premium', 2, 150) $function$;

-- rc__wsel
create or replace function public.rc__wsel()
 returns integer[]
 language sql
 stable
as $function$
  -- les 6 défis de la semaine (mêmes pour tous) ; la semaine du 19/10/2026 garde les 6 d'origine
  select case when public.rc__week() = date '2026-10-19' then array[1, 2, 3, 4, 5, 6]
    else (select array_agg(s.id order by s.id) from
           (select p.id from public.rc__wpool() p order by md5(public.rc__week()::text || '#' || p.id) limit 6) s) end $function$;

-- rc__wkinds
create or replace function public.rc__wkinds()
 returns text[]
 language sql
 stable
as $function$
  select array_agg(p.kind order by u.o) from unnest(public.rc__wsel()) with ordinality u(id, o)
    join public.rc__wpool() p on p.id = u.id $function$;

-- rc__wgoals
create or replace function public.rc__wgoals()
 returns integer[]
 language sql
 stable
as $function$
  select array_agg(p.goal order by u.o) from unnest(public.rc__wsel()) with ordinality u(id, o)
    join public.rc__wpool() p on p.id = u.id $function$;

-- rc__wrewards
create or replace function public.rc__wrewards()
 returns integer[]
 language sql
 stable
as $function$
  select array_agg(p.reward order by u.o) from unnest(public.rc__wsel()) with ordinality u(id, o)
    join public.rc__wpool() p on p.id = u.id $function$;

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
  k := public.rc__wkinds();
  if not (p_kind = any(k)) then return; end if;  -- pas au programme cette semaine
  perform public.rc__wk(p_dev);
  update public.rc_players set w_prog[array_position(k, p_kind)] =
         least(coalesce(w_prog[array_position(k, p_kind)], 0) + p_n, 9999)
   where device = p_dev;
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
  end if;
  return '[]'::jsonb;
end $function$;

-- rc_gift
create or replace function public.rc_gift(p_device text, p_to_pid text, p_sig text)
 returns boolean
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare v public.rc_players; dest public.rc_players; n int;
begin
  perform public.rc__check(p_sig, p_device || '|gift|' || p_to_pid);
  perform public.rc__not_blocked(p_device);
  select * into v from public.rc_players where device = p_device for update;
  if v.device is null then raise exception 'joueur inconnu'; end if;
  n := case when v.gift_day = public.rc__today() then v.gift_n else 0 end;
  if n >= 3 then raise exception 'cadeau déjà offert'; end if;
  select * into dest from public.rc_players where pid = p_to_pid for update;
  if dest.device is null then raise exception 'joueur inconnu'; end if;
  if dest.device = p_device then raise exception 'pas à toi-même'; end if;
  if exists (select 1 from public.rc_gifts g where g.giver = p_device and g.receiver = dest.device
              and (g.created_at at time zone 'Europe/Paris')::date = public.rc__today()) then
    raise exception 'déjà offert à ce joueur';
  end if;
  if (select count(*) from public.rc_gifts g where g.receiver = dest.device and g.opened_at is null) >= 10 then
    raise exception 'trop de cadeaux';
  end if;
  insert into public.rc_gifts (receiver, giver, giver_name) values (dest.device, p_device, v.name);
  update public.rc_players set gift_day = public.rc__today(), gift_n = n + 1 where device = p_device;
  perform public.rc__ev_bump(p_device, 'gifts_sent', 1);  -- défi : paquets offerts
  perform public.rc__wbump(p_device, 'gift', 1);  -- défi de la semaine : cadeaux envoyés
  return true;
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
  end if;
  return public.rc__gamedle_json(p_device) || jsonb_build_object('ok', ok, 'reward', reward, 'answer', case when ok or tries >= 6 then ans end);
end $function$;

-- rc__c4_finish
create or replace function public.rc__c4_finish(p_id bigint, p_winner integer, p_reason text)
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare g public.rc_c4; ok boolean; m int := least(coalesce(public.rc__effect('duel_x'), 1), 5);
begin
  select * into g from public.rc_c4 where id = p_id;
  if g.status <> 'playing' then return; end if;
  ok := g.stake > 0 or public.rc__duel_paid(g.p1, g.p2);
  update public.rc_c4 set status = 'done', winner = p_winner, reason = p_reason, paid = ok where id = p_id;
  if not ok then return; end if;  -- partie amicale : pas de gains
  if p_winner in (1, 2) then perform public.rc__wbump(case when p_winner = 1 then g.p1 else g.p2 end, 'win', 1); end if;
  perform public.rc__wbump(g.p1, 'play', 1);  -- défi : duels joués
  perform public.rc__wbump(g.p2, 'play', 1);
  if g.stake > 0 then  -- ancienne partie avec mise
    if p_winner = 0 then
      update public.rc_players set coins = coins + g.stake where device in (g.p1, g.p2);
    else
      update public.rc_players set coins = coins + g.stake * 2, pixels = pixels + 1
       where device = case when p_winner = 1 then g.p1 else g.p2 end;
    end if;
  elsif p_winner = 0 then
    update public.rc_players set coins = coins + 10 * m where device in (g.p1, g.p2);
  else
    update public.rc_players set coins = coins + 150 * m, pixels = pixels + 1
     where device = case when p_winner = 1 then g.p1 else g.p2 end;
    update public.rc_players set coins = coins + 10 * m
     where device = case when p_winner = 1 then g.p2 else g.p1 end;
  end if;
end $function$;

-- rc__bs_finish
create or replace function public.rc__bs_finish(p_id bigint, p_winner integer, p_reason text)
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare g public.rc_bs; ok boolean; m int := least(coalesce(public.rc__effect('duel_x'), 1), 5);
begin
  select * into g from public.rc_bs where id = p_id;
  if g.status not in ('setup', 'playing') then return; end if;
  ok := g.stake > 0 or public.rc__duel_paid(g.p1, g.p2);
  update public.rc_bs set status = 'done', winner = p_winner, reason = p_reason, paid = ok where id = p_id;
  if not ok then return; end if;  -- partie amicale : pas de gains
  if p_winner in (1, 2) then perform public.rc__wbump(case when p_winner = 1 then g.p1 else g.p2 end, 'win', 1); end if;
  perform public.rc__wbump(g.p1, 'play', 1);  -- défi : duels joués
  perform public.rc__wbump(g.p2, 'play', 1);
  if g.stake > 0 then  -- ancienne partie avec mise
    update public.rc_players set coins = coins + g.stake * 2, pixels = pixels + 1
     where device = case when p_winner = 1 then g.p1 else g.p2 end;
  else
    update public.rc_players set coins = coins + 150 * m, pixels = pixels + 1
     where device = case when p_winner = 1 then g.p1 else g.p2 end;
    update public.rc_players set coins = coins + 10 * m
     where device = case when p_winner = 1 then g.p2 else g.p1 end;
  end if;
end $function$;

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
    is_new := not exists (select 1 from public.rc_owned where device = p_device and card = c);
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
  e jsonb; c text; f int; r int; is_new boolean; got_epic boolean := false; nnew int := 0; s text;
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
    is_new := not exists (select 1 from public.rc_owned where device = p_device and card = c);
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
  insert into public.rc_pack_log (device, kind, sys) values (p_device, pd.kind, pd.sys);  -- stats admin
  update public.rc_players set packs = packs + 1, pity = case when got_epic then 0 else pity + 1 end,
         pixels = pixels + case when public.rc__special_cost(pd.kind) is null then 1 else 0 end
   where device = p_device;
  ev := ev || public.rc__bump(p_device, 'open', 1);
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
  if is_new then perform public.rc__wbump(p_device, 'new', 1); end if;
  perform public.rc__rescore(p_device);
  return jsonb_build_object('card', m.card, 'f', m.finish, 'n', is_new,
                            'coins', (select coins from public.rc_players where device = p_device), 'events', ev);
end $function$;

-- rc_quiz_claim
create or replace function public.rc_quiz_claim(p_device text, p_correct integer, p_sig text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare
  v public.rc_players;
  already int;
  gain int;
begin
  perform public.rc__check(p_sig, p_device || '|quiz|' || p_correct);
  select * into v from public.rc_players where device = p_device for update;
  if v.device is null then raise exception 'joueur inconnu'; end if;
  already := case when v.quiz_day = public.rc__today() then v.quiz_gain else 0 end;
  gain := least(greatest(coalesce(p_correct, 0), 0), 10) * 5;
  gain := least(gain, greatest(0, 100 - already));
  update public.rc_players
     set coins = coins + gain, quiz_day = public.rc__today(), quiz_gain = already + gain, updated_at = now()
   where device = p_device
  returning coins into v.coins;
  perform public.rc__ev_bump(p_device, 'quiz', gain / 5);  -- défi : bonnes réponses (dans la limite du jour)
  perform public.rc__wbump(p_device, 'quiz', gain / 5);
  return jsonb_build_object('gain', gain, 'left', greatest(0, 100 - already - gain), 'coins', v.coins);
end $function$;

-- rc__week_json
CREATE OR REPLACE FUNCTION public.rc__week_json(p_dev text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select jsonb_build_object(
    'kinds', to_jsonb(public.rc__wkinds()), 'goals', to_jsonb(public.rc__wgoals()), 'rewards', to_jsonb(public.rc__wrewards()),
    'prog', to_jsonb(p.w_prog), 'claim', p.w_claim,
    'chest', jsonb_build_object('coins', 500, 'pixels', 2, 'premium', 1),
    'ends', extract(epoch from ((public.rc__week() + 7)::timestamp at time zone 'Europe/Paris'))::bigint,
    'coins', p.coins, 'pixels', p.pixels,
    'gifts', (select count(*)::int from public.rc_gifts g where g.receiver = p_dev and g.opened_at is null))
    from public.rc_players p where p.device = p_dev $function$;

-- ancienne version (par numéro de défi), remplacée par la version par type
drop function if exists public.rc__wbump(text, integer, integer);

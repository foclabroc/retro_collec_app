-- ═══════════════════════════════════════════════════════════════════════════
-- Pixel Trade · 19/10/2026 · admin, récompenses, effets, défis
-- Relançable : create or replace / if not exists partout.
--
--   • Récompenses enrichies (événements, paliers de défi, courrier) :
--       {"coins":500,"pixels":5,"packs":{"premium":1,"star":1},"lots":1,"cards":{"3":1}}
--     paquets : mixte, premium, mystery, star, gold (arrivent dans « Cadeaux »)
--     lots    : lot de 5 paquets mixtes · cards : carte au hasard par rareté (0 à 4)
--   • Effets : promo, holo_x, rare_x, recycle_x, duel_x, lot_free (+ pixels_x2, free_fast)
--   • Défis : sales, trades, recycle, epics, gifts_sent, quiz, console (+ packs, c4_wins, bs_wins, gamedle)
--   • Admin : listes des stats, cadeau ciblé, bandeau, maintenance, recherche de carte,
--             journal admin, paquets ouverts dans la fiche joueur
-- ═══════════════════════════════════════════════════════════════════════════

-- ─── Tables et colonnes ────────────────────────────────────────────────────
alter table public.rc_events add column if not exists reward jsonb not null default '{}'::jsonb;
alter table public.rc_events add column if not exists arg text;            -- promo : type de paquet ; console : id console
alter table public.rc_mail   add column if not exists reward jsonb not null default '{}'::jsonb;
alter table public.rc_mail   add column if not exists grp text;            -- cadeau ciblé : active7, new7, inactive7

create table if not exists public.rc_mail_to (
  mail_id bigint not null references public.rc_mail(id) on delete cascade,
  device text not null,
  primary key (mail_id, device)
);
alter table public.rc_mail_to enable row level security;

create table if not exists public.rc_pack_log (
  id bigserial primary key,
  device text not null,
  kind text,
  sys text,
  at timestamptz not null default now()
);
create index if not exists rc_pack_log_at on public.rc_pack_log (at);
create index if not exists rc_pack_log_dev on public.rc_pack_log (device, at);
alter table public.rc_pack_log enable row level security;

create table if not exists public.rc_admin_log (
  id bigserial primary key,
  device text,
  action text not null,
  at timestamptz not null default now()
);
create index if not exists rc_admin_log_at on public.rc_admin_log (at);
alter table public.rc_admin_log enable row level security;

-- ─── Admin : vérification + journal des actions ────────────────────────────
create or replace function public.rc__admin(p_dev text, p_sig text, p_payload text)
 returns void
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
begin
  perform public.rc__check(p_sig, p_dev || '|admin|' || coalesce(p_payload, ''));
  if not public.rc__is_admin(p_dev) then raise exception 'réservé'; end if;
  -- journal : seulement les actions (pas les lectures)
  if split_part(coalesce(p_payload, ''), '|', 1) in
     ('mail', 'mail2', 'block', 'rename', 'config', 'live', 'mremove', 'maildel', 'pollnew', 'pollclose', 'evsave', 'evactive') then
    insert into public.rc_admin_log (device, action) values (p_dev, left(p_payload, 400));
  end if;
end $function$;

create or replace function public.rc_admin_log_list(p_device text, p_sig text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
begin
  perform public.rc__admin(p_device, p_sig, 'log');
  return coalesce((select jsonb_agg(jsonb_build_object('id', l.id, 'action', l.action, 'at', l.at,
                                                       'by', (select p.name from public.rc_players p where p.device = l.device)) order by l.id desc)
                     from (select * from public.rc_admin_log order by id desc limit 200) l), '[]'::jsonb);
end $function$;

-- ─── Récompenses ───────────────────────────────────────────────────────────
-- Additionne deux récompenses (pièces, pixels, lots, paquets et cartes par clé)
create or replace function public.rc__rw_add(a jsonb, b jsonb)
 returns jsonb
 language plpgsql
 immutable
as $function$
declare r jsonb; k text; v text; m jsonb;
begin
  a := coalesce(a, '{}'::jsonb); b := coalesce(b, '{}'::jsonb);
  r := jsonb_build_object(
    'coins', coalesce((a->>'coins')::int, 0) + coalesce((b->>'coins')::int, 0),
    'pixels', coalesce((a->>'pixels')::int, 0) + coalesce((b->>'pixels')::int, 0),
    'lots', coalesce((a->>'lots')::int, 0) + coalesce((b->>'lots')::int, 0));
  -- paquets
  m := coalesce(a->'packs', '{}'::jsonb);
  for k, v in select key, value from jsonb_each_text(coalesce(b->'packs', '{}'::jsonb)) loop
    m := m || jsonb_build_object(k, coalesce((m->>k)::int, 0) + coalesce(v::int, 0));
  end loop;
  r := r || jsonb_build_object('packs', m);
  -- cartes
  m := coalesce(a->'cards', '{}'::jsonb);
  for k, v in select key, value from jsonb_each_text(coalesce(b->'cards', '{}'::jsonb)) loop
    m := m || jsonb_build_object(k, coalesce((m->>k)::int, 0) + coalesce(v::int, 0));
  end loop;
  return r || jsonb_build_object('cards', m);
end $function$;

-- Vrai si la récompense contient quelque chose
create or replace function public.rc__rw_any(r jsonb)
 returns boolean
 language sql
 immutable
as $function$
  select coalesce((r->>'coins')::int, 0) > 0 or coalesce((r->>'pixels')::int, 0) > 0 or coalesce((r->>'lots')::int, 0) > 0
      or exists (select 1 from jsonb_each_text(coalesce(r->'packs', '{}'::jsonb)) x where x.value::int > 0)
      or exists (select 1 from jsonb_each_text(coalesce(r->'cards', '{}'::jsonb)) x where x.value::int > 0) $function$;

-- Nettoie une récompense venue de la page admin (types connus, bornes)
create or replace function public.rc__rw_clean(r jsonb)
 returns jsonb
 language plpgsql
 immutable
as $function$
declare out jsonb := '{}'::jsonb; m jsonb := '{}'::jsonb; k text; v text; n int;
begin
  if r is null or jsonb_typeof(r) <> 'object' then return '{}'::jsonb; end if;
  n := least(greatest(coalesce((r->>'coins')::int, 0), 0), 100000); if n > 0 then out := out || jsonb_build_object('coins', n); end if;
  n := least(greatest(coalesce((r->>'pixels')::int, 0), 0), 1000);  if n > 0 then out := out || jsonb_build_object('pixels', n); end if;
  n := least(greatest(coalesce((r->>'lots')::int, 0), 0), 5);       if n > 0 then out := out || jsonb_build_object('lots', n); end if;
  for k, v in select key, value from jsonb_each_text(coalesce(r->'packs', '{}'::jsonb)) loop
    n := least(greatest(coalesce(v::int, 0), 0), 10);
    if k in ('mixte', 'premium', 'mystery', 'star', 'gold') and n > 0 then m := m || jsonb_build_object(k, n); end if;
  end loop;
  if m <> '{}'::jsonb then out := out || jsonb_build_object('packs', m); end if;
  m := '{}'::jsonb;
  for k, v in select key, value from jsonb_each_text(coalesce(r->'cards', '{}'::jsonb)) loop
    n := least(greatest(coalesce(v::int, 0), 0), 10);
    if k in ('0', '1', '2', '3', '4') and n > 0 then m := m || jsonb_build_object(k, n); end if;
  end loop;
  if m <> '{}'::jsonb then out := out || jsonb_build_object('cards', m); end if;
  return out;
end $function$;

-- Donne une récompense à un joueur. Renvoie ce qui a été donné (+ les cartes tirées).
create or replace function public.rc__grant(p_dev text, p_reward jsonb)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare
  r jsonb := public.rc__rw_clean(p_reward);
  k text; v text; n int; i int; c text; cards jsonb := '[]'::jsonb;
  lbl text;
begin
  if r = '{}'::jsonb then return jsonb_build_object('cards', cards); end if;
  update public.rc_players
     set coins = coins + coalesce((r->>'coins')::int, 0),
         pixels = pixels + coalesce((r->>'pixels')::int, 0),
         lots = lots + 5 * coalesce((r->>'lots')::int, 0)
   where device = p_dev;
  for k, v in select key, value from jsonb_each_text(coalesce(r->'packs', '{}'::jsonb)) loop
    lbl := case k when 'mixte' then 'mixte' when 'premium' then 'premium' when 'mystery' then 'mystère'
                  when 'star' then 'Étoile' when 'gold' then 'Rétro d''or' end;
    for i in 1 .. v::int loop
      insert into public.rc_gifts (receiver, giver, giver_name, kind) values (p_dev, null, 'Pixel Trade · ' || lbl, k);
    end loop;
  end loop;
  for k, v in select key, value from jsonb_each_text(coalesce(r->'cards', '{}'::jsonb)) loop
    for i in 1 .. v::int loop
      select id into c from public.rc_cards where rarity = k::int and saga is null order by random() limit 1;
      if c is not null then
        perform public.rc__give(p_dev, c, 0, 1);
        cards := cards || jsonb_build_object('c', c, 'r', k::int, 'f', 0);
      end if;
    end loop;
  end loop;
  if jsonb_array_length(cards) > 0 then perform public.rc__rescore(p_dev); end if;
  return r || jsonb_build_object('cards', cards);
end $function$;

-- ─── Effets ────────────────────────────────────────────────────────────────
create or replace function public.rc__effect(p_effect text)
 returns integer
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select max(coalesce(e.effect_value, case p_effect when 'pixels_x2' then 2 when 'free_fast' then 3 when 'promo' then 20
                                                     when 'lot_free' then 1 else 2 end))
    from public.rc_events e
   where e.kind = 'effect' and e.effect = p_effect and public.rc__ev_live(e) $function$;

-- Réduction en % sur un type de paquet (0 sans promo). arg vide ou « all » = tous les paquets.
create or replace function public.rc__promo(p_kind text)
 returns integer
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select least(coalesce(max(coalesce(e.effect_value, 20)), 0), 90)::int
    from public.rc_events e
   where e.kind = 'effect' and e.effect = 'promo' and public.rc__ev_live(e)
     and (coalesce(e.arg, '') in ('', 'all') or e.arg = p_kind) $function$;

create or replace function public.rc__pack_price(k text)
 returns integer
 language sql
 stable
as $function$
  select (case k when 'free' then 0 when 'mixte' then public.rc__cfg('mixte', 100)::int when 'console' then public.rc__cfg('console', 150)::int
                 when 'premium' then public.rc__cfg('premium', 400)::int
                 when 'mystery' then public.rc__cfg('mystery', 120)::int when 'gift' then 0 when 'lot' then 0 end)
         * (100 - public.rc__promo(k)) / 100 $function$;

-- Prix du lot de 5 paquets (promo comprise)
create or replace function public.rc__lot_price()
 returns integer
 language sql
 stable
as $function$ select 500 * (100 - public.rc__promo('lot')) / 100 $function$;

-- Lot gratuit aujourd'hui : samedi, ou effet « lot_free » en cours
create or replace function public.rc__lot_day()
 returns boolean
 language sql
 stable
as $function$ select public.rc__saturday() or public.rc__effect('lot_free') is not null $function$;

create or replace function public.rc__live()
 returns jsonb
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select jsonb_build_object(
    'saga', public.rc__cfg('saga', 3.2), 'holo', public.rc__cfg('holo', 5), 'gold', public.rc__cfg('gold', 0.5),
    'fullart', public.rc__cfg('fullart', 0.2),
    'mixte', public.rc__cfg('mixte', 100), 'console', public.rc__cfg('console', 150),
    'premium', public.rc__cfg('premium', 400), 'mystery', public.rc__cfg('mystery', 120),
    'chest_coins', public.rc__cfg('chest_coins', 500), 'chest_pixels', public.rc__cfg('chest_pixels', 2),
    -- effets en cours (affichage) : réductions par paquet, multiplicateurs
    'promo', jsonb_build_object('mixte', public.rc__promo('mixte'), 'console', public.rc__promo('console'),
                                'premium', public.rc__promo('premium'), 'mystery', public.rc__promo('mystery'), 'lot', public.rc__promo('lot')),
    'holo_x', coalesce(public.rc__effect('holo_x'), 1), 'rare_x', coalesce(public.rc__effect('rare_x'), 1),
    'recycle_x', coalesce(public.rc__effect('recycle_x'), 1), 'duel_x', coalesce(public.rc__effect('duel_x'), 1)) $function$;

create or replace function public.rc__roll(p_min integer)
 returns integer
 language plpgsql
as $function$
declare x float := random() * 100; m float := least(coalesce(public.rc__effect('rare_x'), 1), 5);
begin
  if p_min >= 3 then return case when x < 15 then 4 else 3 end; end if;
  if p_min = 2 then return case when x < 5 then 4 when x < 25 then 3 else 2 end; end if;
  -- normal : légendaire 0,8 %, épique 3,2 %, rare 10 %, peu commune 26 %, commune 60 % (épique et légendaire × effet « rare_x »)
  return case when x < 0.8 * m then 4 when x < 4 * m then 3 when x < 4 * m + 10 then 2 when x < 4 * m + 36 then 1 else 0 end;
end $function$;

create or replace function public.rc__roll_finish()
 returns integer
 language plpgsql
as $function$
declare x float := random(); m float := least(coalesce(public.rc__effect('holo_x'), 1), 5);
        g float := public.rc__cfg('gold', 0.5) / 100 * m;
begin
  return case when x < g then 2 when x < g + public.rc__cfg('holo', 5) / 100 * m then 1 else 0 end;
end $function$;

create or replace function public.rc_buy_lot(p_device text, p_sig text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare v public.rc_players; free boolean; price int := public.rc__lot_price();
begin
  perform public.rc__check(p_sig, p_device || '|lot');
  select * into v from public.rc_players where device = p_device for update;
  if v.device is null then raise exception 'joueur inconnu'; end if;
  free := public.rc__lot_day() and v.lot_free is distinct from public.rc__today();
  if free then
    update public.rc_players set lot_free = public.rc__today(), lots = lots + 5 where device = p_device;
  elsif v.coins < price then
    raise exception 'pas assez de pièces';
  else
    update public.rc_players set coins = coins - price, lots = lots + 5 where device = p_device;
  end if;
  select * into v from public.rc_players where device = p_device;
  return jsonb_build_object('free', free, 'lots', v.lots, 'coins', v.coins);
end $function$;

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
  select coalesce(sum(qty), 0) into total from public.rc_owned where device = p_device and card = p_card;
  if total - p_qty < 1 then raise exception 'dernier exemplaire'; end if;
  if not public.rc__take(p_device, p_card, p_finish, p_qty) then raise exception 'pas assez d''exemplaires'; end if;
  select rarity into r from public.rc_cards where id = p_card;
  gain := public.rc__recycle_value(r, p_finish) * p_qty * least(coalesce(public.rc__effect('recycle_x'), 1), 5);
  update public.rc_players set coins = coins + gain where device = p_device;
  ev := public.rc__bump(p_device, 'recycle', p_qty);
  perform public.rc__rescore(p_device);
  return jsonb_build_object('gain', gain, 'coins', (select coins from public.rc_players where device = p_device), 'events', ev);
end $function$;

create or replace function public.rc_recycle_dupes(p_device text, p_sig text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare
  gain int := 0; n int := 0; rec record; ev jsonb := '[]'::jsonb;
begin
  perform public.rc__check(p_sig, p_device || '|dupes');
  perform 1 from public.rc_players where device = p_device for update;
  for rec in
    select o.card, o.finish, o.qty, c.rarity from public.rc_owned o join public.rc_cards c on c.id = o.card
     where o.device = p_device and o.qty > 1
  loop
    update public.rc_owned set qty = 1 where device = p_device and card = rec.card and finish = rec.finish;
    gain := gain + public.rc__recycle_value(rec.rarity, rec.finish) * (rec.qty - 1);
    n := n + rec.qty - 1;
  end loop;
  gain := gain * least(coalesce(public.rc__effect('recycle_x'), 1), 5);
  if n > 0 then
    update public.rc_players set coins = coins + gain where device = p_device;
    ev := public.rc__bump(p_device, 'recycle', n);
  end if;
  return jsonb_build_object('gain', gain, 'count', n,
                            'coins', (select coins from public.rc_players where device = p_device), 'events', ev);
end $function$;

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
  if p_winner in (1, 2) then perform public.rc__wbump(case when p_winner = 1 then g.p1 else g.p2 end, 4, 1); end if;
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
  if p_winner in (1, 2) then perform public.rc__wbump(case when p_winner = 1 then g.p1 else g.p2 end, 4, 1); end if;
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

-- ─── Défis : compteurs ─────────────────────────────────────────────────────
-- +n sur les défis en cours de cet objectif (console : seulement ceux de cette console)
create or replace function public.rc__ev_bump(p_dev text, p_goal text, p_n integer, p_arg text default null)
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
begin
  if p_dev is null or coalesce(p_n, 0) <= 0 then return; end if;
  insert into public.rc_events_prog (device, event_id, n)
  select p_dev, e.id, p_n from public.rc_events e
   where e.kind = 'goal' and e.goal = p_goal and public.rc__ev_live(e)
     and (p_goal <> 'console' or e.arg = p_arg)
  on conflict (device, event_id) do update set n = public.rc_events_prog.n + excluded.n;
end $function$;

create or replace function public.rc__ev_progress(p_dev text, e rc_events)
 returns integer
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select case e.goal
    when 'c4_wins' then (select count(*)::int from public.rc_c4 g
                          where g.status = 'done' and g.move_at >= e.starts_at and (e.ends_at is null or g.move_at < e.ends_at)
                            and ((g.p1 = p_dev and g.winner = 1) or (g.p2 = p_dev and g.winner = 2)))
    when 'bs_wins' then (select count(*)::int from public.rc_bs g
                          where g.status = 'done' and g.move_at >= e.starts_at and (e.ends_at is null or g.move_at < e.ends_at)
                            and ((g.p1 = p_dev and g.winner = 1) or (g.p2 = p_dev and g.winner = 2)))
    when 'gamedle' then (select count(*)::int from public.rc_gamedle d
                          where d.device = p_dev and d.won
                            and d.day >= (e.starts_at at time zone 'Europe/Paris')::date
                            and (e.ends_at is null or d.day <= (e.ends_at at time zone 'Europe/Paris')::date))
    -- compteurs tenus par le serveur (packs, sales, trades, recycle, epics, gifts_sent, quiz, console)
    else coalesce((select n from public.rc_events_prog where device = p_dev and event_id = e.id), 0) end $function$;

create or replace function public.rc__bump(p_dev text, p_kind text, p_n integer)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
begin
  perform public.rc__wbump(p_dev, case p_kind when 'open' then 1 when 'recycle' then 2 else 3 end, p_n);
  if p_kind = 'open' then
    perform public.rc__ref_check(p_dev);  -- parrainage
    insert into public.rc_daily (day, packs) values (public.rc__today(), p_n)
    on conflict (day) do update set packs = public.rc_daily.packs + p_n;  -- stats admin
  elsif p_kind = 'recycle' then
    perform public.rc__ev_bump(p_dev, 'recycle', p_n);
  end if;
  return '[]'::jsonb;
end $function$;

create or replace function public.rc__wbump(p_dev text, p_i integer, p_n integer)
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
begin
  if p_dev is null or p_n <= 0 then return; end if;
  perform public.rc__wk(p_dev);
  update public.rc_players set w_prog[p_i] = least(coalesce(w_prog[p_i], 0) + p_n, 9999) where device = p_dev;
  if p_i = 6 then perform public.rc__ev_bump(p_dev, 'epics', p_n); end if;  -- paquet avec une épique ou mieux
end $function$;

create or replace function public.rc_pick(p_device text, p_choice integer, p_sig text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare
  v public.rc_players;
  pd public.rc_pending;
  e jsonb; c text; f int; r int; is_new boolean; got_epic boolean := false; s text;
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
  if got_epic then perform public.rc__wbump(p_device, 6, 1); end if;  -- défi : carte épique ou mieux
  ev := ev || public.rc__milestones(p_device);
  perform public.rc__rescore(p_device);
  select * into v from public.rc_players where device = p_device;
  return jsonb_build_object('cards', res, 'choice', p_choice, 'missed', miss, 'kind', pd.kind, 'sys', pd.sys,
                            'coins', v.coins, 'pity', v.pity, 'pixels', v.pixels,
                            'pixel_gain', case when public.rc__special_cost(pd.kind) is null then 1 else 0 end, 'score', v.score, 'events', ev, 'lots', v.lots,
                            'gifts', (select count(*)::int from public.rc_gifts g where g.receiver = p_device and g.opened_at is null));
end $function$;

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
  perform public.rc__rescore(p_device);
  return jsonb_build_object('card', m.card, 'f', m.finish, 'n', is_new,
                            'coins', (select coins from public.rc_players where device = p_device), 'events', ev);
end $function$;

create or replace function public.rc_trade_answer(p_device text, p_id bigint, p_accept boolean, p_sig text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare
  t public.rc_trades; it record; ev jsonb := '[]'::jsonb;
begin
  perform public.rc__check(p_sig, p_device || '|answer|' || p_id || '|' || p_accept);
  select * into t from public.rc_trades x where x.id = p_id and x.receiver = p_device and x.status = 'pending' for update;
  if t.id is null then raise exception 'échange introuvable'; end if;
  if p_accept then
    perform public.rc__not_blocked(t.sender);
    perform public.rc__not_blocked(t.receiver);
  end if;
  if not p_accept then
    update public.rc_trades set status = 'refused', done_at = now() where id = t.id;
    return jsonb_build_object('status', 'refused');
  end if;
  -- verrouille les deux joueurs dans un ordre fixe (pas d'interblocage)
  perform 1 from public.rc_players where device in (t.sender, t.receiver) order by device for update;
  if not public.rc__has(t.sender, t.give) or not public.rc__has(t.receiver, t.want) then
    update public.rc_trades set status = 'failed', done_at = now() where id = t.id;
    return jsonb_build_object('status', 'failed');
  end if;
  for it in select * from public.rc__items(t.give) loop
    perform public.rc__take(t.sender, it.card, it.finish, it.n);
    perform public.rc__give(t.receiver, it.card, it.finish, it.n);
  end loop;
  for it in select * from public.rc__items(t.want) loop
    perform public.rc__take(t.receiver, it.card, it.finish, it.n);
    perform public.rc__give(t.sender, it.card, it.finish, it.n);
  end loop;
  update public.rc_trades set status = 'accepted', done_at = now() where id = t.id;
  ev := ev || public.rc__bump(p_device, 'trade', 1) || public.rc__milestones(p_device);
  perform public.rc__bump(t.sender, 'trade', 1);
  perform public.rc__ev_bump(t.sender, 'trades', 1);    -- défi : échanges
  perform public.rc__ev_bump(t.receiver, 'trades', 1);
  perform public.rc__milestones(t.sender);
  perform public.rc__rescore(t.sender);
  perform public.rc__rescore(t.receiver);
  return jsonb_build_object('status', 'accepted', 'events', ev);
end $function$;

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
  return true;
end $function$;

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
  return jsonb_build_object('gain', gain, 'left', greatest(0, 100 - already - gain), 'coins', v.coins);
end $function$;

-- ─── Événements ────────────────────────────────────────────────────────────
create or replace function public.rc_event_claim(p_device text, p_id bigint, p_sig text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare e public.rc_events; v public.rc_players; rw jsonb := '{}'::jsonb; g jsonb; prog int; done int; st jsonb; i int := 0;
begin
  perform public.rc__check(p_sig, p_device || '|event|' || p_id);
  select * into v from public.rc_players where device = p_device for update;
  if v.device is null then raise exception 'joueur inconnu'; end if;
  select * into e from public.rc_events where id = p_id and active;
  if e.id is null then raise exception 'événement inconnu'; end if;
  if not public.rc__ev_live(e) then raise exception 'événement terminé'; end if;

  if e.kind = 'goal' then
    prog := public.rc__ev_progress(p_device, e);
    insert into public.rc_events_prog (device, event_id) values (p_device, p_id) on conflict do nothing;
    select claimed into done from public.rc_events_prog where device = p_device and event_id = p_id for update;
    for st in select value from jsonb_array_elements(e.steps) loop
      i := i + 1;
      if i > done and prog >= coalesce((st->>'n')::int, 0) then
        rw := public.rc__rw_add(rw, jsonb_build_object('coins', coalesce((st->>'coins')::int, 0), 'pixels', coalesce((st->>'pixels')::int, 0)));
        rw := public.rc__rw_add(rw, st->'reward');
        done := i;
      end if;
    end loop;
    if not public.rc__rw_any(rw) then raise exception 'pas de palier à récupérer'; end if;
    update public.rc_events_prog set claimed = done where device = p_device and event_id = p_id;
  else
    rw := public.rc__rw_add(jsonb_build_object('coins', e.coins, 'pixels', e.pixels), e.reward);
    if not public.rc__rw_any(rw) then raise exception 'pas de récompense'; end if;
    insert into public.rc_events_got (device, event_id) values (p_device, p_id) on conflict do nothing;
    if not found then raise exception 'déjà récupéré'; end if;
  end if;

  g := public.rc__grant(p_device, rw);
  select * into v from public.rc_players where device = p_device;
  return jsonb_build_object('coins', v.coins, 'pixels', v.pixels,
                            'gain_coins', coalesce((g->>'coins')::int, 0), 'gain_pixels', coalesce((g->>'pixels')::int, 0), 'gain', g);
end $function$;

create or replace function public.rc_events_list(p_device text)
 returns jsonb
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select coalesce(jsonb_agg(x.j order by x.o, x.s desc), '[]'::jsonb) from (
    select case when e.starts_at > now() then 1
                when public.rc__ev_live(e) then 0 else 2 end as o,
           e.starts_at as s,
           -- à venir : visible en entier (titre, texte, récompenses), mais rien n'est utilisable avant le début
             jsonb_build_object(
               'id', e.id, 'kind', e.kind, 'title', e.title, 'title_en', e.title_en, 'body', e.body, 'body_en', e.body_en,
               'icon', e.icon, 'color', e.color, 'image', e.image, 'decor', e.decor, 'decor_fx', e.decor_fx,
               'starts_at', e.starts_at, 'ends_at', e.ends_at,
               'coins', e.coins, 'pixels', e.pixels, 'reward', e.reward, 'action', e.action, 'arg', e.arg,
               'effect', e.effect, 'effect_value', coalesce(e.effect_value, case e.effect when 'pixels_x2' then 2 when 'free_fast' then 3
                                                                                          when 'promo' then 20 when 'lot_free' then 1 else 2 end),
               'goal', e.goal, 'steps', e.steps,
               'progress', case when e.kind = 'goal' then public.rc__ev_progress(p_device, e) end,
               'claimed', coalesce((select claimed from public.rc_events_prog where device = p_device and event_id = e.id), 0),
               'live', public.rc__ev_live(e),
               'ended', e.ends_at is not null and e.ends_at <= now(),
               'got', exists (select 1 from public.rc_events_got g where g.device = p_device and g.event_id = e.id),
               'upcoming', e.starts_at > now(),
               'now', now()) as j
      from public.rc_events e
     where e.active
       and (e.ends_at is null or e.ends_at > now() - interval '3 days')
       -- à venir : toujours les 5 prochains, quelle que soit leur date
       and (e.starts_at <= now()
            or e.id in (select f.id from public.rc_events f where f.active and f.starts_at > now() order by f.starts_at limit 5))) x $function$;

create or replace function public.rc_admin_events(p_device text, p_sig text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
begin
  perform public.rc__admin(p_device, p_sig, 'events');
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'id', e.id, 'kind', e.kind, 'title', e.title, 'title_en', e.title_en, 'body', e.body, 'body_en', e.body_en,
             'icon', e.icon, 'color', e.color, 'decor', e.decor, 'starts_at', e.starts_at, 'ends_at', e.ends_at,
             'coins', e.coins, 'pixels', e.pixels, 'reward', e.reward, 'arg', e.arg, 'action', e.action, 'active', e.active,
             'effect', e.effect, 'effect_value', e.effect_value, 'goal', e.goal, 'steps', e.steps,
             'live', public.rc__ev_live(e), 'upcoming', e.starts_at > now(), 'ended', e.ends_at is not null and e.ends_at <= now(),
             'got', (select count(*) from public.rc_events_got g where g.event_id = e.id)) order by e.starts_at)
      from public.rc_events e
     where e.ends_at is null or e.ends_at > now() - interval '7 days'), '[]'::jsonb);
end $function$;

create or replace function public.rc_admin_event_save(p_device text, p_sig text, p_id bigint, p_data text)
 returns bigint
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare j jsonb; v_id bigint := p_id; k text; v_steps jsonb := '[]'::jsonb; st jsonb;
begin
  perform public.rc__admin(p_device, p_sig, 'evsave|' || coalesce(p_id, 0) || '|' || coalesce(p_data, ''));
  j := p_data::jsonb;
  k := coalesce(j->>'kind', 'info');
  if k not in ('info', 'effect', 'goal') then raise exception 'type inconnu'; end if;
  if trim(coalesce(j->>'title', '')) = '' then raise exception 'titre vide'; end if;
  if k = 'effect' and coalesce(j->>'effect', '') not in
     ('pixels_x2', 'free_fast', 'promo', 'holo_x', 'rare_x', 'recycle_x', 'duel_x', 'lot_free') then
    raise exception 'effet inconnu';
  end if;
  if k = 'effect' and j->>'effect' = 'promo' and coalesce(nullif(j->>'arg', ''), 'all') not in ('all', 'mixte', 'console', 'premium', 'mystery', 'lot') then
    raise exception 'paquet inconnu';
  end if;
  if k = 'effect' and nullif(j->>'effect_value', '') is not null and (j->>'effect_value')::int not between 1 and 90 then
    raise exception 'valeur entre 1 et 90';
  end if;
  if k = 'goal' and coalesce(j->>'goal', '') not in
     ('packs', 'c4_wins', 'bs_wins', 'gamedle', 'sales', 'trades', 'recycle', 'epics', 'gifts_sent', 'quiz', 'console') then
    raise exception 'défi inconnu';
  end if;
  if k = 'goal' and j->>'goal' = 'console' and not exists (select 1 from public.rc_cards where sys = j->>'arg') then
    raise exception 'console inconnue';
  end if;
  if (j->>'ends_at') is not null and (j->>'ends_at')::timestamptz <= (j->>'starts_at')::timestamptz then
    raise exception 'la fin doit être après le début';
  end if;
  if k = 'goal' then
    for st in select value from jsonb_array_elements(coalesce(j->'steps', '[]'::jsonb)) loop
      v_steps := v_steps || jsonb_build_array(jsonb_build_object(
        'n', greatest(coalesce((st->>'n')::int, 0), 1),
        'coins', least(greatest(coalesce((st->>'coins')::int, 0), 0), 100000),
        'pixels', least(greatest(coalesce((st->>'pixels')::int, 0), 0), 1000),
        'reward', public.rc__rw_clean(st->'reward')));
    end loop;
  end if;
  if v_id is null then
    insert into public.rc_events (kind, title, starts_at) values (k, j->>'title', coalesce((j->>'starts_at')::timestamptz, now()))
    returning rc_events.id into v_id;
  end if;
  update public.rc_events set
    kind = k, title = left(trim(j->>'title'), 60), title_en = nullif(trim(coalesce(j->>'title_en', '')), ''),
    body = left(coalesce(j->>'body', ''), 600), body_en = nullif(trim(coalesce(j->>'body_en', '')), ''),
    icon = coalesce(nullif(j->>'icon', ''), '🎉'), color = coalesce(nullif(j->>'color', ''), '#EF9F27'),
    decor = nullif(j->>'decor', ''),
    starts_at = coalesce((j->>'starts_at')::timestamptz, starts_at), ends_at = (j->>'ends_at')::timestamptz,
    coins = case when k = 'info' then least(greatest(coalesce((j->>'coins')::int, 0), 0), 100000) else 0 end,
    pixels = case when k = 'info' then least(greatest(coalesce((j->>'pixels')::int, 0), 0), 1000) else 0 end,
    reward = case when k = 'info' then public.rc__rw_clean(j->'reward') else '{}'::jsonb end,
    arg = case when k = 'effect' and j->>'effect' = 'promo' then coalesce(nullif(j->>'arg', ''), 'all')
               when k = 'goal' and j->>'goal' = 'console' then j->>'arg' end,
    action = nullif(j->>'action', ''),
    effect = case when k = 'effect' then j->>'effect' end,
    effect_value = case when k = 'effect' then nullif(j->>'effect_value', '')::int end,
    goal = case when k = 'goal' then j->>'goal' end,
    steps = v_steps,
    active = coalesce((j->>'active')::boolean, true)
  where rc_events.id = v_id;
  return v_id;
end $function$;

-- ─── Courrier (annonce / cadeau) : récompense enrichie + groupe ciblé ──────
-- p_target : all, active7, new7, inactive7, ou pid:<pid>
create or replace function public.rc_admin_mail2(p_device text, p_sig text, p_target text, p_title text, p_body text, p_reward text)
 returns bigint
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare d text; v_id bigint; rw jsonb; t text := coalesce(p_target, 'all');
begin
  perform public.rc__admin(p_device, p_sig, 'mail2|' || t || '|' || coalesce(p_title, '') || '|' || coalesce(p_reward, ''));
  if trim(coalesce(p_title, '')) = '' then raise exception 'titre vide'; end if;
  rw := public.rc__rw_clean(coalesce(nullif(p_reward, ''), '{}')::jsonb);
  if t like 'pid:%' then
    select device into d from public.rc_players where pid = substr(t, 5);
    if d is null then raise exception 'joueur inconnu'; end if;
  elsif t not in ('all', 'active7', 'new7', 'inactive7') then
    raise exception 'groupe inconnu';
  end if;
  insert into public.rc_mail (device, title, body, coins, pixels, packs, reward, grp)
  values (d, left(trim(p_title), 80), left(coalesce(p_body, ''), 600), 0, 0, 0, rw, case when t in ('active7', 'new7', 'inactive7') then t end)
  returning rc_mail.id into v_id;
  if t in ('active7', 'new7', 'inactive7') then
    insert into public.rc_mail_to (mail_id, device)
    select v_id, p.device from public.rc_players p
     where (t = 'active7' and p.seen_at > now() - interval '7 days')
        or (t = 'new7' and p.created_at > now() - interval '7 days')
        or (t = 'inactive7' and (p.seen_at is null or p.seen_at <= now() - interval '7 days'));
  end if;
  return v_id;
end $function$;

create or replace function public.rc_mail_list(p_device text, p_sig text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare v public.rc_players;
begin
  perform public.rc__check(p_sig, p_device || '|mail');
  select * into v from public.rc_players where device = p_device;
  if v.device is null then return '[]'::jsonb; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', m.id, 'title', m.title, 'body', m.body, 'coins', m.coins, 'pixels', m.pixels,
                                        'packs', m.packs, 'reward', m.reward, 'all', m.device is null, 'at', m.created_at) order by m.id)
      from public.rc_mail m
     where (m.device = p_device
            or (m.device is null and m.grp is null and m.created_at > v.created_at and m.created_at > now() - interval '30 days')
            or (m.grp is not null and m.created_at > now() - interval '30 days'
                and exists (select 1 from public.rc_mail_to t where t.mail_id = m.id and t.device = p_device)))
       and not exists (select 1 from public.rc_mail_got g where g.device = p_device and g.mail_id = m.id)), '[]'::jsonb);
end $function$;

create or replace function public.rc_mail_read(p_device text, p_id bigint, p_sig text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare m public.rc_mail; v public.rc_players; i int; g jsonb := '{}'::jsonb;
begin
  perform public.rc__check(p_sig, p_device || '|mailread|' || p_id);
  select * into v from public.rc_players where device = p_device for update;
  if v.device is null then raise exception 'joueur inconnu'; end if;
  select * into m from public.rc_mail x where x.id = p_id
     and (x.device = p_device
          or (x.device is null and x.grp is null)
          or exists (select 1 from public.rc_mail_to t where t.mail_id = x.id and t.device = p_device));
  if m.id is null then raise exception 'message inconnu'; end if;
  insert into public.rc_mail_got (device, mail_id) values (p_device, p_id) on conflict do nothing;
  if found then
    update public.rc_players set coins = coins + m.coins, pixels = pixels + m.pixels where device = p_device;
    for i in 1 .. least(m.packs, 10) loop
      insert into public.rc_gifts (receiver, giver, giver_name, kind) values (p_device, null, 'Pixel Trade', 'premium');
    end loop;
    g := public.rc__grant(p_device, m.reward);
  end if;
  select * into v from public.rc_players where device = p_device;
  return jsonb_build_object('coins', v.coins, 'pixels', v.pixels, 'gain', g);
end $function$;

create or replace function public.rc_admin_mails(p_device text, p_sig text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
begin
  perform public.rc__admin(p_device, p_sig, 'mails');
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', m.id, 'title', m.title, 'body', m.body, 'coins', m.coins, 'pixels', m.pixels,
                                        'packs', m.packs, 'reward', m.reward, 'grp', m.grp, 'at', m.created_at,
                                        'to', case when m.device is null then null else (select p.name from public.rc_players p where p.device = m.device) end,
                                        'sent', case when m.grp is null then null else (select count(*) from public.rc_mail_to t where t.mail_id = m.id) end,
                                        'read', (select count(*) from public.rc_mail_got g where g.mail_id = m.id)) order by m.id desc)
      from (select * from public.rc_mail order by id desc limit 30) m), '[]'::jsonb);
end $function$;

-- ─── Bandeau d'info et maintenance (rc_config) ─────────────────────────────
create or replace function public.rc_admin_set_config(p_device text, p_sig text, p_key text, p_value text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare j jsonb;
begin
  perform public.rc__admin(p_device, p_sig, 'config|' || coalesce(p_key, '') || '|' || coalesce(p_value, ''));
  if p_key = 'min_version' then
    if p_value !~ '^\d+\.\d+\.\d+$' then raise exception 'version invalide (ex. 1.0.12)'; end if;
    insert into public.rc_config (key, value) values ('min_version', to_jsonb(p_value))
    on conflict (key) do update set value = excluded.value;
  elsif p_key = 'banner' then
    -- {"text": "...", "until": "2026-10-20T20:00:00Z"} ; texte vide = pas de bandeau
    j := coalesce(nullif(p_value, ''), '{}')::jsonb;
    insert into public.rc_config (key, value)
    values ('banner', jsonb_build_object('text', left(trim(coalesce(j->>'text', '')), 200), 'until', j->>'until'))
    on conflict (key) do update set value = excluded.value;
  elsif p_key = 'maintenance' then
    -- {"on": true, "msg": "..."}
    j := coalesce(nullif(p_value, ''), '{}')::jsonb;
    insert into public.rc_config (key, value)
    values ('maintenance', jsonb_build_object('on', coalesce((j->>'on')::boolean, false), 'msg', left(coalesce(j->>'msg', ''), 300)))
    on conflict (key) do update set value = excluded.value;
  else
    raise exception 'réglage inconnu';
  end if;
  return public.rc_app_config();
end $function$;

create or replace function public.rc_app_config()
 returns jsonb
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select jsonb_build_object('min_version', coalesce((select value #>> '{}' from public.rc_config where key = 'min_version'), '1.0.0'),
                            'live', public.rc__live(),
                            'banner', (select value from public.rc_config where key = 'banner'
                                        and coalesce(value->>'text', '') <> ''
                                        and (value->>'until' is null or (value->>'until')::timestamptz > now())),
                            'maintenance', (select value from public.rc_config where key = 'maintenance' and (value->>'on')::boolean)) $function$;

-- ─── Lot gratuit : samedi ou effet en cours (pastille de l'onglet Paquets) ─
create or replace function public.rc_notifs(p_device text)
 returns jsonb
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select jsonb_build_object(
    'trades', (select count(*)::int from public.rc_trades t where t.receiver = p_device and t.status = 'pending'),
    'sales', coalesce((
      select jsonb_agg(jsonb_build_object('id', m.id, 'card', m.card, 'f', m.finish, 'price', m.price,
                                          'buyer', (select b.name from public.rc_players b where b.device = m.buyer))
                       order by m.sold_at)
        from public.rc_market m, public.rc_players me
       where me.device = p_device and m.seller = p_device and m.buyer is not null and m.sold_at > me.market_seen), '[]'::jsonb),
    'wheel', (select wheel_day is distinct from public.rc__today() from public.rc_players where device = p_device),
    'gifts', (select count(*)::int from public.rc_gifts g where g.receiver = p_device and g.opened_at is null),
    'gift_from', (select g.giver_name from public.rc_gifts g where g.receiver = p_device and g.opened_at is null order by g.id desc limit 1),
    'gift_last', (select coalesce(max(g.id), 0) from public.rc_gifts g where g.receiver = p_device),
    'gifts_left', (select 3 - case when gift_day = public.rc__today() then gift_n else 0 end from public.rc_players where device = p_device),
    'can_gift', (select gift_day is distinct from public.rc__today() or gift_n < 3 from public.rc_players where device = p_device),
    'week', coalesce(public.rc__wk_ready(p_device), 0),
    'reacts', coalesce(public.rc__reacts_new(p_device), 0),
    'lots', (select lots from public.rc_players where device = p_device),
    'free', public.rc__free_in(p_device) = 0,
    'free_in', public.rc__free_in(p_device),
    'free_at', (select coalesce(extract(epoch from last_free_at)::bigint, 0) from public.rc_players where device = p_device),
    'lot_free', (select public.rc__lot_day() and lot_free is distinct from public.rc__today() from public.rc_players where device = p_device),
    'lot_price', public.rc__lot_price(),
    'chat', (select count(*)::int from public.rc_chat c, public.rc_players me
              where me.device = p_device and c.id > me.chat_seen and c.device <> p_device and not c.hidden),
    'chat_last', (select coalesce(max(c.id), 0) from public.rc_chat c where not c.hidden),
    'mention', (select coalesce(max(c.id), 0) from public.rc_chat c, public.rc_players me
                 where me.device = p_device and c.id > me.chat_seen and c.device <> p_device and not c.hidden
                   and public.rc__name_key(c.msg) like '%@' || me.name_key || '%')) $function$;

-- ─── Stats cliquables : listes ─────────────────────────────────────────────
-- p_kind : active7, today, new7, packs, sales, duels
create or replace function public.rc_admin_stat_list(p_device text, p_sig text, p_kind text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare today date := public.rc__today();
begin
  perform public.rc__admin(p_device, p_sig, 'statlist|' || coalesce(p_kind, ''));
  if p_kind in ('active7', 'today') then
    return coalesce((select jsonb_agg(jsonb_build_object('pid', p.pid, 'name', p.name, 'avatar', p.avatar, 'at', p.seen_at,
                                                         'n', p.packs, 'coins', p.coins) order by p.seen_at desc)
                       from public.rc_players p
                      where (p_kind = 'active7' and p.seen_at > now() - interval '7 days')
                         or (p_kind = 'today' and (p.seen_at at time zone 'Europe/Paris')::date = today)), '[]'::jsonb);
  elsif p_kind = 'new7' then
    return coalesce((select jsonb_agg(jsonb_build_object('pid', p.pid, 'name', p.name, 'avatar', p.avatar, 'at', p.created_at,
                                                         'n', p.packs, 'ref', (select s.name from public.rc_players s where s.device = p.referrer))
                                      order by p.created_at desc)
                       from public.rc_players p where p.created_at > now() - interval '7 days'), '[]'::jsonb);
  elsif p_kind = 'packs' then
    return coalesce((select jsonb_agg(jsonb_build_object('pid', p.pid, 'name', p.name, 'avatar', p.avatar, 'at', x.last,
                                                         'n', x.n, 'kinds', x.kinds) order by x.n desc, x.last desc)
                       from (select l.device, count(*)::int n, max(l.at) last, jsonb_object_agg(l.kind, l.c) kinds
                               from (select device, coalesce(kind, '?') kind, count(*)::int c, max(at) at from public.rc_pack_log
                                      where (at at time zone 'Europe/Paris')::date = today group by device, coalesce(kind, '?')) l
                              group by l.device) x
                       join public.rc_players p on p.device = x.device), '[]'::jsonb);
  elsif p_kind = 'sales' then
    return coalesce((select jsonb_agg(jsonb_build_object('pid', s.pid, 'name', s.name, 'avatar', s.avatar, 'at', m.sold_at,
                                                         'other', b.name, 'other_pid', b.pid, 'card', m.card, 'f', m.finish, 'price', m.price)
                                      order by m.sold_at desc)
                       from public.rc_market m
                       join public.rc_players s on s.device = m.seller
                       left join public.rc_players b on b.device = m.buyer
                      where m.buyer is not null and (m.sold_at at time zone 'Europe/Paris')::date = today), '[]'::jsonb);
  elsif p_kind = 'duels' then
    return coalesce((select jsonb_agg(jsonb_build_object('pid', a.pid, 'name', a.name, 'avatar', a.avatar, 'at', d.move_at,
                                                         'other', b.name, 'other_pid', b.pid, 'game', d.jeu, 'winner', d.winner, 'reason', d.reason)
                                      order by d.move_at desc)
                       from (select 'c4' jeu, p1, p2, status, reason, winner, move_at from public.rc_c4
                             union all select 'bs', p1, p2, status, reason, winner, move_at from public.rc_bs) d
                       join public.rc_players a on a.device = d.p1
                       left join public.rc_players b on b.device = d.p2
                      where d.status = 'done' and coalesce(d.reason, '') not in ('declined', 'cancelled', 'expired')
                        and (d.move_at at time zone 'Europe/Paris')::date = today), '[]'::jsonb);
  end if;
  raise exception 'liste inconnue';
end $function$;

-- ─── Chercher une carte ────────────────────────────────────────────────────
create or replace function public.rc_admin_card(p_device text, p_sig text, p_card text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
begin
  perform public.rc__admin(p_device, p_sig, 'card|' || coalesce(p_card, ''));
  return jsonb_build_object(
    'total', (select coalesce(sum(qty), 0) from public.rc_owned where card = p_card),
    'players', (select count(distinct device) from public.rc_owned where card = p_card and qty > 0),
    'finishes', coalesce((select jsonb_object_agg(f, n) from (select finish f, sum(qty)::int n from public.rc_owned
                                                                where card = p_card group by finish) x), '{}'::jsonb),
    'owners', coalesce((select jsonb_agg(jsonb_build_object('pid', p.pid, 'name', p.name, 'avatar', p.avatar, 'n', x.n, 'f', x.f) order by x.n desc)
                          from (select device, sum(qty)::int n, jsonb_object_agg(finish, qty) f from public.rc_owned
                                 where card = p_card and qty > 0 group by device order by sum(qty) desc limit 100) x
                          join public.rc_players p on p.device = x.device), '[]'::jsonb),
    'open', (select count(*) from public.rc_market where card = p_card and buyer is null),
    'sales', coalesce((select jsonb_agg(jsonb_build_object('price', m.price, 'f', m.finish, 'at', m.sold_at) order by m.sold_at desc)
                         from (select * from public.rc_market where card = p_card and buyer is not null order by sold_at desc limit 10) m), '[]'::jsonb));
end $function$;

-- ─── Fiche joueur : + paquets ouverts ──────────────────────────────────────
create or replace function public.rc_admin_player(p_device text, p_sig text, p_pid text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare v public.rc_players;
begin
  perform public.rc__admin(p_device, p_sig, 'player|' || coalesce(p_pid, ''));
  select * into v from public.rc_players where pid = p_pid;
  if v.device is null then raise exception 'joueur inconnu'; end if;
  return jsonb_build_object(
    'pid', v.pid, 'name', v.name, 'avatar', v.avatar, 'created_at', v.created_at, 'seen_at', v.seen_at,
    'coins', v.coins, 'pixels', v.pixels, 'packs', v.packs, 'cards', v.cards, 'score', v.score, 'days', v.days, 'blocked', v.blocked,
    'referrer', (select s.name from public.rc_players s where s.device = v.referrer),
    'events', coalesce((select jsonb_agg(e order by e->>'at' desc) from (
      select e from (
        select jsonb_build_object('at', coalesce(m.sold_at, m.created_at), 'kind', case when m.seller = v.device then (case when m.buyer is null then 'listing' else 'sold' end) else 'bought' end,
                 'other', (select o.name from public.rc_players o where o.device = case when m.seller = v.device then m.buyer else m.seller end),
                 'card', m.card, 'f', m.finish, 'price', m.price,
                 'avg', public.rc__avg_price(m.card, m.finish, m.id)) e
          from public.rc_market m where v.device in (m.seller, m.buyer)
        union all
        select jsonb_build_object('at', coalesce(t.done_at, t.created_at), 'kind', 'trade', 'status', t.status,
                 'other', (select o.name from public.rc_players o where o.device = case when t.sender = v.device then t.receiver else t.sender end),
                 'gave', case when t.sender = v.device then t.give else t.want end,
                 'got', case when t.sender = v.device then t.want else t.give end,
                 'gave_v', public.rc__items_value(case when t.sender = v.device then t.give else t.want end),
                 'got_v', public.rc__items_value(case when t.sender = v.device then t.want else t.give end))
          from public.rc_trades t where v.device in (t.sender, t.receiver)
        union all
        select jsonb_build_object('at', g.created_at, 'kind', case when g.giver = v.device then 'gift_out' else 'gift_in' end,
                 'other', coalesce((select o.name from public.rc_players o where o.device = case when g.giver = v.device then g.receiver else g.giver end), g.giver_name))
          from public.rc_gifts g where v.device in (g.giver, g.receiver)
        union all
        select jsonb_build_object('at', x.created_at, 'kind', 'duel', 'game', x.jeu, 'status', x.status, 'reason', x.reason,
                 'other', (select o.name from public.rc_players o where o.device = case when x.p1 = v.device then x.p2 else x.p1 end),
                 'result', case when x.winner = 0 then 'draw' when x.winner is null then null
                                when (x.winner = 1) = (x.p1 = v.device) then 'win' else 'loss' end)
          from (select 'c4' jeu, p1, p2, status, reason, winner, created_at from public.rc_c4
                union all select 'bs', p1, p2, status, reason, winner, created_at from public.rc_bs) x
         where v.device in (x.p1, x.p2)
        union all
        select jsonb_build_object('at', c.created_at, 'kind', 'chat', 'msg', c.msg, 'hidden', c.hidden, 'reports', c.reports)
          from public.rc_chat c where c.device = v.device
        union all
        select jsonb_build_object('at', l.at, 'kind', 'pack', 'pack', l.kind, 'sys', l.sys)
          from public.rc_pack_log l where l.device = v.device
      ) all_e order by e->>'at' desc limit 100) s), '[]'::jsonb));
end $function$;

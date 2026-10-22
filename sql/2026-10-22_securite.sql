-- 2026-10-22 : sécurité (audit du 22/10). Relançable.
--  1. Cadeau de version : seulement pour un compte créé AVANT la sortie de cette version.
--  2. Création de comptes limitée à 5 par jour et par adresse IP (IP lue dans l'en-tête X-Forwarded-For
--     mis par Caddy, gardée seulement en empreinte sha256 dans rc_ip_log).
--  3. Bourse (achat / vente), cadeaux, échanges : interdits aux comptes de moins de 24 h (rc__not_new).
--  5. Connexion par mot de passe : 5 erreurs bloquent ce pseudo 15 min POUR CETTE IP seulement
--     (+ une IP qui rate 30 fois en 1 h est bloquée 1 h, tous pseudos confondus).
--  (4. limite de connexions par IP : dans le relais rc-realtime.)

-- ─── Outils ───────────────────────────────────────────────────────────────
-- empreinte de l'IP du client (null si appel hors API, ex. psql)
create or replace function public.rc__ip()
 returns text
 language sql
 stable
 set search_path to 'public', 'extensions'
as $function$
  select case when ip = '' then null else encode(extensions.digest('ip|' || ip, 'sha256'), 'hex') end
    from (select trim(split_part(coalesce(nullif(current_setting('request.headers', true), '')::json ->> 'x-forwarded-for', ''), ',', 1)) as ip) x $function$;
alter function public.rc__ip() owner to rc_owner;

create table if not exists public.rc_ip_log (
  id    bigserial   primary key,
  ip    text        not null,
  kind  text        not null,   -- 'signup' | 'login_fail'
  name  text,                   -- name_key visé (login_fail)
  at    timestamptz not null default now()
);
create index if not exists rc_ip_log_ip on public.rc_ip_log (ip, kind, at);
alter table public.rc_ip_log owner to rc_owner;
revoke all on public.rc_ip_log from public;
revoke all on sequence public.rc_ip_log_id_seq from public;

create or replace function public.rc__not_new(p_device text)
 returns void
 language plpgsql
 stable security definer
 set search_path to 'public'
as $function$
begin
  if exists (select 1 from public.rc_players where device = p_device and created_at > now() - interval '24 hours') then
    raise exception 'compte trop récent : possible 24 h après la création du compte';
  end if;
end $function$;
alter function public.rc__not_new(text) owner to rc_owner;

-- ─── 1. Cadeau de version ─────────────────────────────────────────────────
create or replace function public.rc_upgrade_gift(p_device text, p_ver text, p_sig text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare
  v_rw jsonb; v_out timestamptz;
begin
  perform public.rc__check(p_sig, p_device || '|upgrade|' || p_ver);
  if not exists (select 1 from public.rc_players where device = p_device) then raise exception 'joueur inconnu'; end if;
  -- cadeau par version (même JSON que les récompenses → rc__grant) + date de sortie de la version :
  -- seuls les comptes créés avant la sortie le reçoivent (un nouveau compte ne peut pas réclamer les anciens)
  select x.rw, x.out_at into v_rw, v_out from (values
    ('1.0.16', '{"coins":500}'::jsonb, timestamptz '2026-10-21 09:30+00'),
    ('1.0.18', '{"coins":600,"pixels":8,"packs":{"premium":1}}'::jsonb, timestamptz '2026-10-22 06:45+00')
  ) x(ver, rw, out_at) where x.ver = p_ver;
  if v_rw is null then return jsonb_build_object('coins', 0); end if;
  if exists (select 1 from public.rc_players where device = p_device and created_at >= v_out) then
    return jsonb_build_object('coins', 0);
  end if;
  insert into public.rc_upgrade_got (device, ver) values (p_device, p_ver) on conflict do nothing;
  if not found then return jsonb_build_object('coins', 0); end if;
  perform public.rc__grant(p_device, v_rw);
  return jsonb_build_object('coins', coalesce((v_rw->>'coins')::int, 0), 'reward', v_rw);
end $function$;
-- ─── 2. Création de comptes : 5 par jour et par IP ───────────────────────
create or replace function public.rc_me(p_device text, p_sig text, p_have text default null)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  v public.rc_players;
  v_pid text := left(encode(extensions.digest(p_device, 'sha256'), 'hex'), 16);
  v_name text;
  ev jsonb := '[]'::jsonb;
  bonus int;
  v_owned jsonb;
  v_oh text;
begin
  perform public.rc__check(p_sig, p_device || '|me');
  if length(coalesce(p_device, '')) <> 32 then raise exception 'invalide'; end if;
  if not exists (select 1 from public.rc_players where device = p_device) then
    if public.rc__ip() is not null then
      if (select count(*) from public.rc_ip_log where ip = public.rc__ip() and kind = 'signup' and at > now() - interval '1 day') >= 5 then
        raise exception 'trop de comptes créés depuis cette connexion, réessaie demain';
      end if;
      insert into public.rc_ip_log (ip, kind) values (public.rc__ip(), 'signup');
    end if;
    v_name := 'Collec-' || upper(left(v_pid, 4));
    insert into public.rc_players (device, pid, name, name_key)
    values (p_device, v_pid, v_name, public.rc__name_key(v_name)) on conflict do nothing;
    ev := ev || jsonb_build_object('type', 'welcome', 'coins', 500);
  end if;
  perform public.rc__day(p_device);
  update public.rc_players set seen_at = now() where device = p_device;  -- « en ligne » dans l'immeuble
  select * into v from public.rc_players where device = p_device for update;
  if v.last_login is distinct from public.rc__today() then
    v.streak := case when v.last_login = public.rc__today() - 1 then v.streak + 1 else 1 end;
    bonus := case when v.streak % 7 = 0 then 200 else 50 end;
    update public.rc_players set streak = v.streak, last_login = public.rc__today(), coins = coins + bonus, days = days + 1
     where device = p_device;
    ev := ev || jsonb_build_object('type', 'login', 'streak', v.streak, 'coins', bonus);
    perform public.rc__ref_check(p_device);  -- parrainage
    insert into public.rc_daily (day, players) values (public.rc__today(), 1)
    on conflict (day) do update set players = public.rc_daily.players + 1;  -- stats admin
  end if;
  select * into v from public.rc_players where device = p_device;
  v_owned := public.rc__owned_json(p_device);
  v_oh := md5(v_owned::text);
  return jsonb_build_object(
    'pid', v.pid, 'name', v.name, 'avatar', v.avatar, 'coins', v.coins, 'score', v.score,
    'cards', v.cards, 'packs', v.packs, 'pity', v.pity, 'streak', v.streak,
    'free', public.rc__free_in(p_device) = 0, 'free_in', public.rc__free_in(p_device),
    'showcase', v.showcase, 'pixels', v.pixels,
    'missions', jsonb_build_object('open', v.d_open, 'recycle', v.d_recycle, 'trade', v.d_trade, 'done', v.d_done),
    'milestones', (select coalesce(jsonb_agg(jsonb_build_array(sys, step)), '[]'::jsonb)
                     from public.rc_milestones where device = p_device),
    'oh', v_oh,
    'events', ev)
    -- collection envoyée seulement si elle a changé depuis la dernière fois (p_have = son empreinte)
    || case when p_have is distinct from v_oh then jsonb_build_object('owned', v_owned) else '{}'::jsonb end;
end $function$;

-- ─── 3. Comptes de moins de 24 h : pas de Bourse, cadeaux ni échanges ────
CREATE OR REPLACE FUNCTION public.rc_market_add(p_device text, p_card text, p_finish integer, p_price integer, p_sig text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare v_id bigint;
begin
  perform public.rc__check(p_sig, p_device || '|sell|' || p_card || '|' || p_finish || '|' || p_price);
  perform public.rc__not_new(p_device);
  perform public.rc__not_blocked(p_device);
  perform 1 from public.rc_players where device = p_device for update;
  if (select count(*) from public.rc_market where seller = p_device and buyer is null) >= 12 then
    raise exception 'trop de lots';
  end if;
  if not public.rc__take(p_device, p_card, p_finish, 1) then raise exception 'carte non possédée'; end if;
  insert into public.rc_market (seller, card, finish, price) values (p_device, p_card, p_finish, p_price)
  returning rc_market.id into v_id;
  perform public.rc__rescore(p_device);
  return v_id;
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
  perform public.rc__not_new(p_device);
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

create or replace function public.rc_market_buy_many(p_device text, p_items text, p_sig text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare
  it text; parts text[]; v_card text; v_f int; v_max int; o record; r jsonb;
  got jsonb := '[]'::jsonb; skip jsonb := '[]'::jsonb; ev jsonb := '[]'::jsonb; n int := 0;
begin
  perform public.rc__check(p_sig, p_device || '|buymany|' || coalesce(p_items, ''));
  perform public.rc__not_new(p_device);
  perform public.rc__not_blocked(p_device);
  foreach it in array array_remove(string_to_array(coalesce(p_items, ''), ','), '') loop
    n := n + 1;
    if n > 30 then exit; end if;
    parts := string_to_array(it, ':');
    v_card := parts[1];
    v_f := coalesce(nullif(parts[2], '')::int, 0);
    v_max := coalesce(nullif(parts[3], '')::int, 0);
    select x.id, x.price into o from public.rc_market x
     where x.card = v_card and x.finish = v_f and x.buyer is null and x.seller <> p_device
     order by x.price, x.created_at limit 1;
    if o.id is null then
      skip := skip || jsonb_build_object('card', v_card, 'f', v_f, 'why', 'sold');
    elsif o.price > v_max then
      skip := skip || jsonb_build_object('card', v_card, 'f', v_f, 'why', 'price', 'price', o.price);
    elsif (select coins from public.rc_players where device = p_device) < o.price then
      skip := skip || jsonb_build_object('card', v_card, 'f', v_f, 'why', 'coins');
    else
      begin
        r := public.rc__market_buy1(p_device, o.id);
        if r is null then
          skip := skip || jsonb_build_object('card', v_card, 'f', v_f, 'why', 'sold');
        else
          ev := ev || coalesce(r -> 'events', '[]'::jsonb);
          got := got || (r - 'events');
        end if;
      exception when others then
        skip := skip || jsonb_build_object('card', v_card, 'f', v_f, 'why', 'error', 'msg', sqlerrm);
      end;
    end if;
  end loop;
  if jsonb_array_length(got) > 0 then perform public.rc__rescore(p_device); end if;
  return jsonb_build_object('bought', got, 'skipped', skip, 'events', ev,
                            'coins', (select coins from public.rc_players where device = p_device));
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
  perform public.rc__not_new(p_device);
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

CREATE OR REPLACE FUNCTION public.rc_trade_offer(p_device text, p_to_pid text, p_give text, p_want text, p_sig text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare v_to text; v_id bigint; ng int; nw int;
begin
  perform public.rc__check(p_sig, p_device || '|offer|' || p_to_pid || '|' || coalesce(p_give, '') || '|' || coalesce(p_want, ''));
  perform public.rc__not_new(p_device);
  perform public.rc__not_blocked(p_device);
  select device into v_to from public.rc_players where pid = p_to_pid;
  if v_to is null then raise exception 'joueur inconnu'; end if;
  if v_to = p_device then raise exception 'pas avec toi-même'; end if;
  select coalesce(sum(n), 0) into ng from public.rc__items(p_give);
  select coalesce(sum(n), 0) into nw from public.rc__items(p_want);
  if ng > 5 or nw > 5 or ng + nw = 0 then raise exception 'échange invalide'; end if;
  if exists (select 1 from public.rc__items(p_give) i where not exists (select 1 from public.rc_cards c where c.id = i.card))
     or exists (select 1 from public.rc__items(p_want) i where not exists (select 1 from public.rc_cards c where c.id = i.card)) then
    raise exception 'carte inconnue';
  end if;
  if not public.rc__has(p_device, p_give) then raise exception 'tu ne possèdes pas ces cartes'; end if;
  if (select count(*) from public.rc_trades where sender = p_device and status = 'pending') >= 10 then
    raise exception 'trop d''échanges en attente';
  end if;
  insert into public.rc_trades (sender, receiver, give, want) values (p_device, v_to, coalesce(p_give, ''), coalesce(p_want, ''))
  returning rc_trades.id into v_id;
  return v_id;
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
    perform public.rc__not_new(t.sender);
    perform public.rc__not_new(t.receiver);
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
  perform public.rc__tbump(t.sender, 'trades', 1);    -- trophée : échanges
  perform public.rc__tbump(t.receiver, 'trades', 1);
  perform public.rc__milestones(t.sender);
  perform public.rc__rescore(t.sender);
  perform public.rc__rescore(t.receiver);
  return jsonb_build_object('status', 'accepted', 'events', ev);
end $function$;

-- ─── 5. Connexion : blocage par pseudo ET par IP ─────────────────────────
create or replace function public.rc_login(p_name text, p_hash text)
 returns text
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare v public.rc_players; k text; v_ip text := coalesce(public.rc__ip(), 'local');
begin
  k := public.rc__name_key(left(trim(coalesce(p_name, '')), 24));
  -- une IP qui a raté 30 connexions en 1 h (tous pseudos) attend ; 5 ratés sur ce pseudo en 15 min aussi
  if (select count(*) from public.rc_ip_log l where l.ip = v_ip and l.kind = 'login_fail' and l.at > now() - interval '1 hour') >= 30
     or (select count(*) from public.rc_ip_log l where l.ip = v_ip and l.kind = 'login_fail' and l.name = k and at > now() - interval '15 minutes') >= 5 then
    raise exception 'trop de tentatives';
  end if;
  select * into v from public.rc_players where name_key = k;
  if v.device is null or v.pass_hash is null or extensions.crypt(coalesce(p_hash, ''), v.pass_hash) <> v.pass_hash then
    insert into public.rc_ip_log (ip, kind, name) values (v_ip, 'login_fail', k);
    if random() < 0.02 then delete from public.rc_ip_log where at < now() - interval '2 days'; end if;  -- ménage
    if v.device is null or v.pass_hash is null then raise exception 'identifiants incorrects'; end if;
    return null;  -- (pas d'exception : sinon l'erreur notée serait annulée)
  end if;
  update public.rc_players set pass_fail = 0, pass_lock = null where device = v.device;
  return v.device;
end $function$;

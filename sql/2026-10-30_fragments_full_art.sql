-- Fragments de full art : le recyclage ne donne plus de pièces mais des fragments
-- (même table que rc__recycle_value, 1 pièce d'avant = 1 fragment, effet recycle_x gardé).
-- Fabriquer une full art (épique / légendaire de console, hors sagas) : 3 000 / 10 000 fragments.
-- Relançable.

alter table public.rc_players add column if not exists fragments integer not null default 0;

create or replace function public.rc__fragment_cost(r integer)
 returns integer
 language sql
 immutable
as $function$
  select case r when 3 then 3000 when 4 then 10000 else null end $function$;
alter function public.rc__fragment_cost(integer) owner to rc_owner;

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
  update public.rc_players set fragments = fragments + gain where device = p_device;
  ev := public.rc__bump(p_device, 'recycle', p_qty);
  perform public.rc__rescore(p_device);
  return jsonb_build_object('gain', gain, 'fragments', (select fragments from public.rc_players where device = p_device), 'events', ev);
end $function$;
alter function public.rc_recycle(text, text, integer, integer, text) owner to rc_owner;

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
    update public.rc_players set fragments = fragments + gain where device = p_device;
    ev := public.rc__bump(p_device, 'recycle', n);
  end if;
  return jsonb_build_object('gain', gain, 'count', n,
                            'fragments', (select fragments from public.rc_players where device = p_device), 'events', ev);
end $function$;
alter function public.rc_recycle_dupes(text, text) owner to rc_owner;

create or replace function public.rc_craft_full(p_device text, p_card text, p_sig text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare
  r int; cost int; v public.rc_players; is_new boolean; ev jsonb := '[]'::jsonb;
begin
  perform public.rc__check(p_sig, p_device || '|craftfull|' || p_card);
  select rarity into r from public.rc_cards where id = p_card and saga is null;
  cost := public.rc__fragment_cost(r);
  if cost is null then raise exception 'full art impossible pour cette carte'; end if;
  select * into v from public.rc_players where device = p_device for update;
  if exists (select 1 from public.rc_owned where device = p_device and card = p_card and finish = 3 and qty > 0) then
    raise exception 'full art déjà possédée';
  end if;
  if v.fragments < cost then raise exception 'pas assez de fragments'; end if;
  is_new := public.rc__is_new(p_device, p_card, 3);
  update public.rc_players set fragments = fragments - cost where device = p_device;
  perform public.rc__give(p_device, p_card, 3, 1);
  perform public.rc__rescore(p_device);
  return jsonb_build_object('n', is_new, 'fragments', (select fragments from public.rc_players where device = p_device), 'events', ev);
end $function$;
alter function public.rc_craft_full(text, text, text) owner to rc_owner;

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
    'showcase', v.showcase, 'pixels', v.pixels, 'fragments', v.fragments,
    'missions', jsonb_build_object('open', v.d_open, 'recycle', v.d_recycle, 'trade', v.d_trade, 'done', v.d_done),
    'milestones', (select coalesce(jsonb_agg(jsonb_build_array(sys, step)), '[]'::jsonb)
                     from public.rc_milestones where device = p_device),
    'oh', v_oh,
    'events', ev)
    -- collection envoyée seulement si elle a changé depuis la dernière fois (p_have = son empreinte)
    || case when p_have is distinct from v_oh then jsonb_build_object('owned', v_owned) else '{}'::jsonb end;
end $function$;
alter function public.rc_me(text, text, text) owner to rc_owner;

notify pgrst, 'reload schema';

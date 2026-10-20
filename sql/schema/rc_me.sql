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
end $function$

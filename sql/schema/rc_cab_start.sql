create or replace function public.rc_cab_start(p_device text, p_pid text, p_sig text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare o public.rc_players; v_game text; v_comm boolean := false; v_id bigint; v_day timestamptz;
begin
  perform public.rc__check(p_sig, p_device || '|cabstart|' || coalesce(p_pid, ''));
  if not exists (select 1 from public.rc_players where device = p_device) then raise exception 'joueur inconnu'; end if;
  select * into o from public.rc_players where pid = p_pid;
  if o.device is null then raise exception 'joueur inconnu'; end if;
  v_game := public.rc__cab_game(o.cab_game, o.pid);
  v_day := public.rc__today()::timestamp at time zone 'Europe/Paris';
  if (select count(*) from public.rc_cab_runs where device = p_device and started_at > now() - interval '1 minute') >= 12 then
    raise exception 'trop de parties, attends un peu';
  end if;
  if o.device <> p_device
     and not exists (select 1 from public.rc_players where device = p_device and blocked)
     and not exists (select 1 from public.rc_players where device = p_device and created_at > now() - interval '24 hours')
     and (select count(*) from public.rc_cab_runs where owner = o.device and device = p_device and comm and started_at >= v_day) < 5
     and (select count(*) from public.rc_cab_runs where owner = o.device and comm and started_at >= v_day) < 30 then
    v_comm := true;
  end if;
  if random() < 0.01 then perform public.rc__cab_clean(); end if;
  insert into public.rc_cab_runs (device, owner, game, comm) values (p_device, o.device, v_game, v_comm) returning id into v_id;
  if v_comm then
    update public.rc_players set coins = coins + 1, updated_at = now() where device = o.device;
  end if;
  return jsonb_build_object('run', v_id, 'game', v_game,
    'rec', (select r.score from public.rc__cab_rec(o.device, v_game) r));
end $function$;

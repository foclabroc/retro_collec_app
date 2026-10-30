create or replace function public.rc_rn_solo_start(p_device text, p_sig text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare v_day date := public.rc__today(); v_run bigint;
begin
  perform public.rc__check(p_sig, p_device || '|rnsstart');
  if not exists (select 1 from public.rc_players where device = p_device) then raise exception 'joueur inconnu'; end if;
  perform public.rc__not_blocked(p_device);
  begin
    perform public.rc__rn_solo_pay();
  exception when others then null;
  end;
  if exists (select 1 from public.rc_rn_runs where device = p_device and started_at > now() - interval '3 seconds') then
    raise exception 'trop vite';
  end if;
  if (select count(*) from public.rc_rn_runs where device = p_device and day = v_day) >= 300 then
    raise exception 'trop de parties';
  end if;
  insert into public.rc_rn_runs (device, day) values (p_device, v_day) returning id into v_run;
  if random() < 0.01 then delete from public.rc_rn_runs where started_at < now() - interval '3 days'; end if;
  return jsonb_build_object('run', v_run, 'seed', public.rc__rn_seed(v_day), 'day', v_day,
    'best', coalesce((select score from public.rc_rn_best where day = v_day and device = p_device), 0));
end $function$;

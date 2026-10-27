create or replace function public.rc_rj_invite(p_device text, p_pid text, p_sig text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare v public.rc_players; o public.rc_players; gid bigint;
begin
  perform public.rc__check(p_sig, p_device || '|rjinv|' || coalesce(p_pid, ''));
  select * into v from public.rc_players where device = p_device;
  select * into o from public.rc_players where pid = p_pid;
  if v.device is null or o.device is null then raise exception 'joueur inconnu'; end if;
  if o.device = v.device then raise exception 'pas contre toi-même'; end if;
  perform public.rc__not_blocked(p_device);
  if o.blocked then raise exception 'joueur indisponible'; end if;
  if not o.rj_ok then raise exception 'joueur à mettre à jour'; end if;
  if coalesce(o.seen_at < now() - interval '2 minutes', true) then raise exception 'joueur hors ligne'; end if;
  if public.rc__duel_busy(v.device) then raise exception 'tu es déjà en partie'; end if;
  if public.rc__duel_busy(o.device) then raise exception 'joueur déjà en partie'; end if;
  if exists (select 1 from public.rc_rj g where g.status in ('invite', 'playing')
              and ((g.p1 = v.device and g.p2 = o.device) or (g.p1 = o.device and g.p2 = v.device))
              and now() <= case when g.status = 'invite' then g.created_at + interval '2 minutes'
                                else g.end_at + interval '30 seconds' end) then
    raise exception 'partie déjà en cours';
  end if;
  if (select count(*) from public.rc_rj g where g.status in ('invite', 'playing') and v.device in (g.p1, g.p2)
        and g.created_at > now() - interval '10 minutes') >= 5 then
    raise exception 'trop de défis';
  end if;
  update public.rc_players set seen_at = now() where device = p_device;
  insert into public.rc_rj (p1, p2) values (v.device, o.device) returning id into gid;
  return public.rc__rj_json((select g from public.rc_rj g where g.id = gid), p_device);
end $function$;

CREATE OR REPLACE FUNCTION public.rc_c4_invite(p_device text, p_pid text, p_mode text, p_sig text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare v public.rc_players; o public.rc_players; gid bigint;
begin
  perform public.rc__check(p_sig, p_device || '|c4inv|' || coalesce(p_pid, '') || '|' || coalesce(p_mode, ''));
  if p_mode not in ('live', 'turn') then raise exception 'mode inconnu'; end if;
  select * into v from public.rc_players where device = p_device;
  select * into o from public.rc_players where pid = p_pid;
  if v.device is null or o.device is null then raise exception 'joueur inconnu'; end if;
  if o.device = v.device then raise exception 'pas contre toi-même'; end if;
  if p_mode = 'live' and coalesce(o.seen_at < now() - interval '2 minutes', true) then raise exception 'joueur hors ligne'; end if;
  if exists (select 1 from public.rc_c4 g where g.status in ('invite', 'playing') and g.mode = p_mode
              and ((g.p1 = v.device and g.p2 = o.device) or (g.p1 = o.device and g.p2 = v.device))
              and now() <= case when g.status = 'invite' then g.created_at + public.rc__c4_invite_limit(g.mode)
                                else g.move_at + public.rc__c4_limit(g.mode) end) then
    raise exception 'partie déjà en cours';
  end if;
  if (select count(*) from public.rc_c4 g where g.status in ('invite', 'playing') and v.device in (g.p1, g.p2)) >= 15 then
    raise exception 'trop de parties';
  end if;
  update public.rc_players set seen_at = now() where device = p_device;
  insert into public.rc_c4 (p1, p2, mode) values (v.device, o.device, p_mode) returning id into gid;
  return public.rc__c4_json((select g from public.rc_c4 g where g.id = gid), p_device);
end $function$

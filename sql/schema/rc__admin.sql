create or replace function public.rc__admin(p_dev text, p_sig text, p_payload text)
 returns void language plpgsql security definer set search_path to 'public', 'extensions'
as $$
declare v_role text; a text := split_part(coalesce(p_payload, ''), '|', 1); k text;
begin
  perform public.rc__check(p_sig, p_dev || '|admin|' || coalesce(p_payload, ''));
  if not public.rc__is_admin(p_dev) then raise exception 'réservé'; end if;
  select coalesce(r.role, 'full') into v_role
    from public.rc_admins r join public.rc_players p on p.pid = r.pid where p.device = p_dev limit 1;
  if coalesce(v_role, 'full') <> 'full' then
    k := case a when 'x' then 'x:' || split_part(p_payload, '|', 2)
                when 'config' then 'config:' || split_part(p_payload, '|', 2) else a end;
    if not (k = any(public.rc__adm_allowed(v_role))) then raise exception 'action réservée à un autre rôle d''admin'; end if;
  end if;
  -- journal : seulement les actions (pas les lectures ; celles de rc_admin_x sont notées par rc_admin_x)
  if a in ('mail', 'mail2', 'block', 'rename', 'config', 'live', 'mremove', 'maildel', 'pollnew', 'pollclose', 'evsave', 'evactive',
           'toursave', 'tourcancel', 'chatact') then
    insert into public.rc_admin_log (device, action) values (p_dev, left(p_payload, 400));
  end if;
end $$;

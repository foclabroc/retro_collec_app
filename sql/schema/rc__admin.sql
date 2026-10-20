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

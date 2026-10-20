CREATE OR REPLACE FUNCTION public.rc_admin_event_active(p_device text, p_sig text, p_id bigint, p_on boolean)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  perform public.rc__admin(p_device, p_sig, 'evactive|' || p_id || '|' || case when p_on then '1' else '0' end);
  update public.rc_events set active = p_on where id = p_id;
  return found;
end $function$

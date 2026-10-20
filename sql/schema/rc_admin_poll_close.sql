CREATE OR REPLACE FUNCTION public.rc_admin_poll_close(p_device text, p_sig text, p_id bigint)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  perform public.rc__admin(p_device, p_sig, 'pollclose|' || p_id);
  update public.rc_polls set closed = true where id = p_id;
  return found;
end $function$

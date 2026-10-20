CREATE OR REPLACE FUNCTION public.rc_admin_check(p_device text, p_sig text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  perform public.rc__check(p_sig, p_device || '|admin|check');
  return public.rc__is_admin(p_device);
end $function$

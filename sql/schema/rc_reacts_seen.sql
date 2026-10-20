CREATE OR REPLACE FUNCTION public.rc_reacts_seen(p_device text, p_sig text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  perform public.rc__check(p_sig, p_device || '|rseen');
  update public.rc_players set react_seen = now() where device = p_device;
end $function$

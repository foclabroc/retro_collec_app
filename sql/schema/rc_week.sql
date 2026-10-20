CREATE OR REPLACE FUNCTION public.rc_week(p_device text, p_sig text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  perform public.rc__check(p_sig, p_device || '|week');
  if not exists (select 1 from public.rc_players where device = p_device) then raise exception 'joueur inconnu'; end if;
  perform public.rc__wk(p_device);
  return public.rc__week_json(p_device);
end $function$

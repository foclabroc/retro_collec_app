CREATE OR REPLACE FUNCTION public.rc_ref_info(p_device text, p_sig text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  perform public.rc__check(p_sig, p_device || '|ref');
  if not exists (select 1 from public.rc_players where device = p_device) then raise exception 'joueur inconnu'; end if;
  return public.rc__ref_json(p_device);
end $function$

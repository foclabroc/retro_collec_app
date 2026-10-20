CREATE OR REPLACE FUNCTION public.rc_pending_get(p_device text, p_sig text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare pd public.rc_pending;
begin
  perform public.rc__check(p_sig, p_device || '|pending');
  select * into pd from public.rc_pending where device = p_device;
  if pd.device is null then return null; end if;
  return jsonb_build_object('choose', jsonb_array_length(pd.packs), 'kind', pd.kind, 'sys', pd.sys, 'resumed', true);
end $function$

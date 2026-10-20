CREATE OR REPLACE FUNCTION public.rc_market_cancel(p_device text, p_id bigint, p_sig text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare m public.rc_market;
begin
  perform public.rc__check(p_sig, p_device || '|cancel|' || p_id);
  delete from public.rc_market x where x.id = p_id and x.seller = p_device and x.buyer is null returning * into m;
  if m.id is null then return false; end if;
  perform public.rc__give(p_device, m.card, m.finish, 1);
  perform public.rc__rescore(p_device);
  return true;
end $function$

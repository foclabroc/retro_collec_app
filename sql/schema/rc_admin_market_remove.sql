CREATE OR REPLACE FUNCTION public.rc_admin_market_remove(p_device text, p_sig text, p_id bigint)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare m public.rc_market;
begin
  perform public.rc__admin(p_device, p_sig, 'mremove|' || p_id);
  delete from public.rc_market x where x.id = p_id and x.buyer is null returning * into m;
  if m.id is null then return false; end if;
  perform public.rc__give(m.seller, m.card, m.finish, 1);
  perform public.rc__rescore(m.seller);
  return true;
end $function$

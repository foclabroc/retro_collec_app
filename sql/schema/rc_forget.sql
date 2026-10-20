CREATE OR REPLACE FUNCTION public.rc_forget(p_device text, p_sig text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare n int;
begin
  perform public.rc__check(p_sig, p_device || '|forget');
  delete from public.rc_players p
   where p.device = p_device and p.packs = 0 and p.cards = 0
     and not exists (select 1 from public.rc_owned o where o.device = p.device)
     and not exists (select 1 from public.rc_market m where m.seller = p.device or m.buyer = p.device)
     and not exists (select 1 from public.rc_trades t where t.sender = p.device or t.receiver = p.device);
  get diagnostics n = row_count;
  return n > 0;
end $function$

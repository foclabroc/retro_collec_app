CREATE OR REPLACE FUNCTION public.rc_trade_cancel(p_device text, p_id bigint, p_sig text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  perform public.rc__check(p_sig, p_device || '|tcancel|' || p_id);
  update public.rc_trades set status = 'cancelled', done_at = now()
   where id = p_id and sender = p_device and status = 'pending';
  return found;
end $function$

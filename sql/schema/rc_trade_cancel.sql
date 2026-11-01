create or replace function public.rc_trade_cancel(p_device text, p_id bigint, p_sig text)
 returns boolean
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare t public.rc_trades;
begin
  perform public.rc__check(p_sig, p_device || '|tcancel|' || p_id);
  select * into t from public.rc_trades where id = p_id and sender = p_device and status = 'pending' for update;
  if t.id is null then return false; end if;
  update public.rc_trades set status = 'cancelled', done_at = now() where id = t.id;
  perform public.rc__trade_return(t.id);
  return true;
end $function$

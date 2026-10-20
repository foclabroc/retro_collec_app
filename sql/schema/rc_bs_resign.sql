CREATE OR REPLACE FUNCTION public.rc_bs_resign(p_device text, p_id bigint, p_sig text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare g public.rc_bs;
begin
  perform public.rc__check(p_sig, p_device || '|bsresign|' || p_id);
  perform public.rc__bs_settle(p_id);
  select * into g from public.rc_bs where id = p_id for update;
  if g.id is null or p_device not in (g.p1, g.p2) then raise exception 'partie inconnue'; end if;
  if g.status in ('setup', 'playing') then
    perform public.rc__bs_finish(p_id, case when g.p1 = p_device then 2 else 1 end, 'resign');
  end if;
  return public.rc__bs_out(p_id, p_device);
end $function$

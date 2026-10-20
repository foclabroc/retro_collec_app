CREATE OR REPLACE FUNCTION public.rc__c4_settle(p_id bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare g public.rc_c4;
begin
  select * into g from public.rc_c4 where id = p_id for update;
  if g.id is null then return; end if;
  if g.status = 'invite' and now() > g.created_at + public.rc__c4_invite_limit(g.mode) then
    update public.rc_c4 set status = 'done', reason = 'expired' where id = p_id;
  elsif g.status = 'playing' and now() > g.move_at + public.rc__c4_limit(g.mode) then
    perform public.rc__c4_finish(p_id, 3 - g.turn, 'timeout');
  end if;
end $function$

CREATE OR REPLACE FUNCTION public.rc_c4_resign(p_device text, p_id bigint, p_sig text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare g public.rc_c4;
begin
  perform public.rc__check(p_sig, p_device || '|c4resign|' || p_id);
  perform public.rc__c4_settle(p_id);
  select * into g from public.rc_c4 where id = p_id for update;
  if g.id is null or p_device not in (g.p1, g.p2) then raise exception 'partie inconnue'; end if;
  if g.status = 'playing' then
    perform public.rc__c4_finish(p_id, case when g.p1 = p_device then 2 else 1 end, 'resign');
  end if;
  select * into g from public.rc_c4 where id = p_id;
  return public.rc__c4_json(g, p_device) || jsonb_build_object('coins', (select coins from public.rc_players where device = p_device));
end $function$

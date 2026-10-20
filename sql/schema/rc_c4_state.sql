CREATE OR REPLACE FUNCTION public.rc_c4_state(p_device text, p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare g public.rc_c4;
begin
  update public.rc_players set seen_at = now() where device = p_device;
  perform public.rc__c4_settle(p_id);
  select * into g from public.rc_c4 where id = p_id and (p1 = p_device or p2 = p_device);
  if g.id is null then raise exception 'partie inconnue'; end if;
  return public.rc__c4_json(g, p_device) || jsonb_build_object('coins', (select coins from public.rc_players where device = p_device));
end $function$

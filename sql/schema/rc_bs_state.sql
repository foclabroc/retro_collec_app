CREATE OR REPLACE FUNCTION public.rc_bs_state(p_device text, p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  update public.rc_players set seen_at = now() where device = p_device;
  perform public.rc__bs_settle(p_id);
  if not exists (select 1 from public.rc_bs where id = p_id and (p1 = p_device or p2 = p_device)) then raise exception 'partie inconnue'; end if;
  return public.rc__bs_out(p_id, p_device);
end $function$

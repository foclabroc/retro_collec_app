create or replace function public.rc_rj_state(p_device text, p_id bigint)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare g public.rc_rj;
begin
  update public.rc_players set seen_at = now() where device = p_device;
  perform public.rc__rj_settle(p_id);
  select * into g from public.rc_rj where id = p_id and (p1 = p_device or p2 = p_device);
  if g.id is null then raise exception 'partie inconnue'; end if;
  return public.rc__rj_json(g, p_device) || jsonb_build_object('coins', (select coins from public.rc_players where device = p_device));
end $function$;

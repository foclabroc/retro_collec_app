create or replace function public.rc_tour_get(p_id bigint, p_device text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
begin
  perform public.rc__tour_tick();
  if not exists (select 1 from public.rc_tour where id = p_id) then raise exception 'tournoi inconnu'; end if;
  return public.rc__tour_json(p_id, p_device, true);
end $function$;

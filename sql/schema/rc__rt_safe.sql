create or replace function public.rc__rt_safe(p_topic text, p_event text, p_payload jsonb)
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
begin
  perform public.rc__rt_send(p_topic, p_event, p_payload);
exception when others then
  null; -- relais indisponible : le polling de secours prend le relais
end $function$;

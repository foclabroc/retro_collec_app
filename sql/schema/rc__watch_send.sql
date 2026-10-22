create or replace function public.rc__watch_send(p_game text, p_id bigint, p_event text, p_payload jsonb)
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare r record;
begin
  perform public.rc__rt_safe(public.rc__rt_watch_topic(p_game, p_id), p_event, p_payload);
  for r in select * from public.rc__watch_game(p_game, p_id) loop
    if r.p1 is not null then perform public.rc__rt_safe(public.rc__rt_topic(r.p1), p_event, p_payload); end if;
    if r.p2 is not null then perform public.rc__rt_safe(public.rc__rt_topic(r.p2), p_event, p_payload); end if;
  end loop;
end $function$;

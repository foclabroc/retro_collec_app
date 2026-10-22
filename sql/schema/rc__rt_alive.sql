create or replace function public.rc__rt_alive(p_topics text[])
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
begin
  update public.rc_players set seen_at = now()
   where public.rc__rt_topic(device) = any(p_topics) and (seen_at is null or seen_at < now() - interval '20 seconds');
  begin
    perform public.rc__tour_tick();
  exception when others then null;  -- jamais bloquant pour la présence
  end;
end $function$;

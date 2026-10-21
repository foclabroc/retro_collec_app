create or replace function public.rc__rt_gone(p_topic text)
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
begin
  update public.rc_players set seen_at = now() - interval '80 seconds'
   where seen_at > now() - interval '80 seconds' and public.rc__rt_topic(device) = p_topic;
  if found then perform public.rc__rt_safe('rc_all', 'online', '{}'::jsonb); end if;
end $function$;

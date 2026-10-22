create or replace function public.rc__rt_alive(p_topics text[])
 returns void
 language sql
 security definer
 set search_path to 'public'
as $function$
  update public.rc_players set seen_at = now()
   where public.rc__rt_topic(device) = any(p_topics) and (seen_at is null or seen_at < now() - interval '20 seconds') $function$

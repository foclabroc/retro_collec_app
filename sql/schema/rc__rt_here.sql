create or replace function public.rc__rt_here(p_topic text)
 returns void
 language sql
 security definer
 set search_path to 'public'
as $function$
  update public.rc_players set seen_at = now()
   where public.rc__rt_topic(device) = p_topic and (seen_at is null or seen_at < now() - interval '5 seconds') $function$

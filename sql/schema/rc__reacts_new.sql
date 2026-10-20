CREATE OR REPLACE FUNCTION public.rc__reacts_new(p_dev text)
 RETURNS integer
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select count(*)::int from public.rc_feed_react r join public.rc_feed f on f.id = r.feed_id, public.rc_players me
   where me.device = p_dev and f.device = p_dev and r.device <> p_dev and r.at > me.react_seen $function$

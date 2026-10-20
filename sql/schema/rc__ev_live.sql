CREATE OR REPLACE FUNCTION public.rc__ev_live(e rc_events)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$ select e.active and e.starts_at <= now() and (e.ends_at is null or e.ends_at > now()) $function$

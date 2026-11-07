create or replace function public.rc__sunday()
 returns boolean language sql stable
as $function$ select extract(isodow from now() at time zone 'Europe/Paris') = 7 $function$;

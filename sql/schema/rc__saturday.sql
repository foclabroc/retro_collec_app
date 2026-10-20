CREATE OR REPLACE FUNCTION public.rc__saturday()
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  select extract(isodow from now() at time zone 'Europe/Paris') = 6 $function$

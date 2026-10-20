CREATE OR REPLACE FUNCTION public.rc__today()
 RETURNS date
 LANGUAGE sql
 STABLE
AS $function$
  select (now() at time zone 'Europe/Paris')::date $function$

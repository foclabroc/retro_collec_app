CREATE OR REPLACE FUNCTION public.rc__week()
 RETURNS date
 LANGUAGE sql
 STABLE
AS $function$
  select date_trunc('week', now() at time zone 'Europe/Paris')::date $function$

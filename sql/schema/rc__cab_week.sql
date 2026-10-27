create or replace function public.rc__cab_week()
 returns date
 language sql
 stable
as $function$
  select date_trunc('week', public.rc__today())::date $function$;

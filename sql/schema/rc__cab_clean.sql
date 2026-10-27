create or replace function public.rc__cab_clean()
 returns void
 language sql
 security definer
 set search_path to 'public'
as $function$
  delete from public.rc_cab_runs where started_at < now() - interval '30 days';
  delete from public.rc_cab_best where week < public.rc__cab_week() - 35;
  delete from public.rc_cab_paid where day < public.rc__today() - 7; $function$;

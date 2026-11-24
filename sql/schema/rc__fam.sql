create or replace function public.rc__fam(f integer)
 returns integer
 language sql
 immutable
as $function$
  select case when coalesce(f, 0) < 3 then 0 else f end $function$;

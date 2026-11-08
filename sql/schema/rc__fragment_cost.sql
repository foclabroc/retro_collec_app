create or replace function public.rc__fragment_cost(r integer)
 returns integer
 language sql
 immutable
as $function$
  select case r when 3 then 1500 when 4 then 4000 else null end $function$;

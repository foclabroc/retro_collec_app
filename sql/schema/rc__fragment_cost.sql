create or replace function public.rc__fragment_cost(r integer)
 returns integer
 language sql
 immutable
as $function$
  select case r when 3 then 3000 when 4 then 10000 else null end $function$;

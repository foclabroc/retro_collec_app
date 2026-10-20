create or replace function public.rc__wgoals()
 returns integer[]
 language sql
 stable
as $function$
  select array_agg(p.goal order by u.o) from unnest(public.rc__wsel()) with ordinality u(id, o)
    join public.rc__wpool() p on p.id = u.id $function$;
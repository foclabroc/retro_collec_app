create or replace function public.rc__wkinds()
 returns text[]
 language sql
 stable
as $function$
  select array_agg(p.kind order by u.o) from unnest(public.rc__wsel()) with ordinality u(id, o)
    join public.rc__wpool() p on p.id = u.id $function$;
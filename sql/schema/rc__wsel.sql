create or replace function public.rc__wsel()
 returns integer[]
 language sql
 stable
as $function$
  -- les 6 défis de la semaine (mêmes pour tous) ; la semaine du 19/10/2026 garde les 6 d'origine
  select case when public.rc__week() = date '2026-10-19' then array[1, 2, 3, 4, 5, 6]
    else (select array_agg(s.id order by s.id) from
           (select p.id from public.rc__wpool() p order by md5(public.rc__week()::text || '#' || p.id) limit 6) s) end $function$;
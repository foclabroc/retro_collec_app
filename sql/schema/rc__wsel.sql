create or replace function public.rc__wsel()
 returns integer[] language sql stable security definer set search_path to 'public' as $$
  -- les 6 défis de la semaine (mêmes pour tous) : figés par l'admin (rc_config « wsel_fix »), sinon tirés parmi les défis actifs
  select coalesce(
    (select array_agg(v::int order by v::int)
       from jsonb_array_elements_text((select value -> (public.rc__week()::text) from public.rc_config where key = 'wsel_fix')) v),
    case when public.rc__week() = date '2026-10-19' then array[1, 2, 3, 4, 5, 6]
         else (select array_agg(s.id order by s.id) from (
                 select p.id from public.rc__wpool() p
                  where p.id not in (select (e->>'id')::int from jsonb_array_elements(coalesce((select value from public.rc_config where key = 'wpool'), '[]'::jsonb)) e
                                      where coalesce((e->>'off')::boolean, false))
                  order by md5(public.rc__week()::text || '#' || p.id) limit 6) s) end)
$$;

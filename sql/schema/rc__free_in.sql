create or replace function public.rc__free_in(p_dev text)
 returns integer language sql stable security definer set search_path to 'public' as $$
  select coalesce((select greatest(0, ceil(extract(epoch from (last_free_at
           + make_interval(hours => coalesce(public.rc__effect('free_fast'), public.rc__cfg('free_hours', 6))::int) - now()))))::int
         from public.rc_players where device = p_dev), 0)
$$;

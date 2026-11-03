create or replace function public.rc__wheel_in(p_device text)
 returns integer language sql stable security definer set search_path to 'public' as $$
  -- secondes avant le prochain tour (0 = disponible) ; avant la bascule : un tour par jour
  select coalesce((
    select case when p.wheel_at is not null
                then greatest(0, ceil(extract(epoch from p.wheel_at + make_interval(hours => public.rc__cfg('wheel_hours', 12)::int) - now()))::int)
                when p.wheel_day is not distinct from public.rc__today() then (public.rc__cfg('wheel_hours', 12) * 3600)::int
                else 0 end
      from public.rc_players p where p.device = p_device), 0)
$$;

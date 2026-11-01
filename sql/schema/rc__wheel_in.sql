create or replace function public.rc__wheel_in(p_device text)
 returns integer
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  -- secondes avant le prochain tour (0 = disponible) : 12 h après le dernier ; avant la bascule : un tour par jour
  select coalesce((
    select case when p.wheel_at is not null then greatest(0, ceil(extract(epoch from p.wheel_at + interval '12 hours' - now()))::int)
                when p.wheel_day is not distinct from public.rc__today() then 43200
                else 0 end
      from public.rc_players p where p.device = p_device), 0) $function$;

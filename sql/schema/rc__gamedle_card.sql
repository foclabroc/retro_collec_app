create or replace function public.rc__gamedle_card(p_day date)
 returns text language sql stable security definer set search_path to 'public' as $$
  select coalesce((select card from public.rc_gamedle_force where day = p_day),
                  (select id from public.rc_cards where saga is null and rarity >= case when p_day >= date '2026-10-17' then 3 else 2 end
                    order by md5(id || p_day::text) limit 1))
$$;

create or replace function public.rc__rj_solo_prize(p_place integer)
 returns jsonb language sql stable security definer set search_path to 'public' as $$
  select coalesce((select value -> (p_place::text) from public.rc_config where key = 'solo_prize'),
                  case p_place when 1 then '{"coins":500,"pixels":2}'::jsonb when 2 then '{"coins":300,"pixels":1}'::jsonb
                               when 3 then '{"coins":100}'::jsonb end)
$$;

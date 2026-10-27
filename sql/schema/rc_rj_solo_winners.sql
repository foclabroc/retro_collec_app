create or replace function public.rc_rj_solo_winners(p_days integer default 30)
 returns jsonb
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select coalesce(jsonb_agg(x.j order by x.day desc), '[]'::jsonb) from (
    select w.day, jsonb_build_object('day', w.day,
             'list', jsonb_agg(jsonb_build_object('place', w.place, 'pid', p.pid, 'name', p.name, 'avatar', p.avatar,
                                                  'score', w.score, 'reward', w.reward) order by w.place)) as j
      from public.rc_rj_wins w join public.rc_players p on p.device = w.device
     where w.day >= public.rc__today() - least(greatest(coalesce(p_days, 30), 1), 90)
     group by w.day) x $function$;

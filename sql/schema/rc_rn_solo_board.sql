create or replace function public.rc_rn_solo_board(p_device text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v_day date := public.rc__today(); my int; rk int;
begin
  begin
    perform public.rc__rn_solo_pay();
  exception when others then null;
  end;
  select score into my from public.rc_rn_best where day = v_day and device = p_device;
  if my is not null then
    select count(*) + 1 into rk from public.rc_rn_best b
     where b.day = v_day and (b.score > my or (b.score = my and b.at < (select at from public.rc_rn_best where day = v_day and device = p_device)));
  end if;
  return jsonb_build_object(
    'day', v_day, 'now', now(), 'best', coalesce(my, 0), 'rank', rk,
    'players', (select count(*) from public.rc_rn_best where day = v_day),
    'prizes', jsonb_build_array(public.rc__rj_solo_prize(1), public.rc__rj_solo_prize(2), public.rc__rj_solo_prize(3)),
    'top', coalesce((select jsonb_agg(jsonb_build_object('pid', p.pid, 'name', p.name, 'avatar', p.avatar, 'score', b.score,
                                                         'me', b.device = p_device) order by b.score desc, b.at asc)
                       from (select * from public.rc_rn_best where day = v_day order by score desc, at asc limit 10) b
                       join public.rc_players p on p.device = b.device), '[]'::jsonb),
    'yesterday', coalesce((select jsonb_agg(jsonb_build_object('place', w.place, 'pid', p.pid, 'name', p.name, 'avatar', p.avatar,
                                                               'score', w.score, 'reward', w.reward, 'me', w.device = p_device) order by w.place)
                             from public.rc_rn_wins w join public.rc_players p on p.device = w.device
                            where w.day = v_day - 1), '[]'::jsonb));
end $function$;

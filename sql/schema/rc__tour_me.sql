create or replace function public.rc__tour_me(p_device text)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to 'public'
as $function$
declare r record; me int;
begin
  select m.*, t.name, t.game, t.rounds into r
    from public.rc_tour_matches m join public.rc_tour t on t.id = m.tid
   where t.status = 'running' and m.status in ('wait', 'play') and p_device in (m.p1, m.p2)
   order by m.id desc limit 1;
  if r.id is not null then
    me := case when r.p1 = p_device then 1 else 2 end;
    return jsonb_build_object(
      'tid', r.tid, 'name', r.name, 'game', r.game, 'mid', r.id, 'round', r.round, 'rounds', r.rounds, 'best', r.best,
      'status', r.status, 'gid', case when r.status = 'play' then r.game_id end,
      'ready', case when me = 1 then r.ready1 is not null else r.ready2 is not null end,
      'opp_ready', case when me = 1 then r.ready2 is not null else r.ready1 is not null end,
      'my_w', case when me = 1 then r.w1 else r.w2 end, 'opp_w', case when me = 1 then r.w2 else r.w1 end,
      'deadline', r.start_at + interval '3 minutes', 'now', now(),
      'opp', public.rc__pinfo(case when me = 1 then r.p2 else r.p1 end));
  end if;
  select t.id, t.name, t.game, t.start_at into r
    from public.rc_tour t join public.rc_tour_players tp on tp.tid = t.id and tp.device = p_device
   where t.status = 'open' and t.start_at <= now() + interval '10 minutes'
   order by t.start_at limit 1;
  if r.id is not null then
    return jsonb_build_object('tid', r.id, 'name', r.name, 'game', r.game, 'soon', r.start_at, 'now', now());
  end if;
  -- tournoi fini depuis moins de 15 min où je suis sur le podium : fenêtre de félicitations (une fois, côté appli)
  select t.id, t.name, t.game, tp.place, t.lots, t.pot, t.split, t.second into r
    from public.rc_tour t join public.rc_tour_players tp on tp.tid = t.id and tp.device = p_device
   where t.status = 'done' and t.ended_at > now() - interval '15 minutes' and tp.place is not null
   order by t.ended_at desc limit 1;
  if r.id is not null then
    return jsonb_build_object('tid', r.id, 'name', r.name, 'game', r.game, 'done', true, 'place', r.place,
      'reward', coalesce(r.lots -> (r.place::text), '{}'::jsonb),
      'pot', case when r.pot <= 0 then 0
                  when r.place = 1 then case when r.split >= 100 or r.second is null then r.pot else floor(r.pot * r.split / 100.0)::int end
                  when r.place = 2 and r.split < 100 then r.pot - floor(r.pot * r.split / 100.0)::int
                  else 0 end,
      'now', now());
  end if;
  return null;
end $function$;

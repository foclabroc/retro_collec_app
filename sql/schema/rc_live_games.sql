create or replace function public.rc_live_games()
 returns jsonb
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select coalesce(jsonb_agg(x.j order by x.at desc), '[]'::jsonb) from (
    select g.created_at as at, jsonb_build_object('game', 'c4', 'id', g.id, 'phase', g.status, 'moves', g.moves,
             'p1', public.rc__pinfo(g.p1), 'p2', public.rc__pinfo(g.p2)) as j
      from public.rc_c4 g
     where g.mode = 'live' and g.status = 'playing' and now() <= g.move_at + interval '60 seconds'
    union all
    select g.created_at, jsonb_build_object('game', 'bs', 'id', g.id, 'phase', g.status, 'moves', g.moves,
             'p1', public.rc__pinfo(g.p1), 'p2', public.rc__pinfo(g.p2))
      from public.rc_bs g
     where g.mode = 'live' and g.status in ('setup', 'playing') and now() <= g.move_at + interval '2 minutes'
  ) x $function$;

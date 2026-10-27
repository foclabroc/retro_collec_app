create or replace function public.rc__rj_json(g public.rc_rj, p_device text)
 returns jsonb
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select jsonb_build_object(
    'id', g.id, 'mode', g.mode, 'status', g.status,
    'side', case when g.p1 = p_device then 1 else 2 end,
    'winner', g.winner, 'reason', g.reason, 'stake', g.stake, 'paid', g.paid,
    'friendly', case when g.stake = 0 and g.status <> 'done' then public.rc__duel_why(g.p1, g.p2) end,
    'moves', g.moves, 'seed', g.seed, 'start_at', g.start_at, 'end_at', g.end_at,
    'h_me', case when g.p1 = p_device then g.h1 else g.h2 end,
    'h_opp', case when g.p1 = p_device then g.h2 else g.h1 end,
    'dead_me', case when g.p1 = p_device then g.dead1 is not null else g.dead2 is not null end,
    'dead_opp', case when g.p1 = p_device then g.dead2 is not null else g.dead1 is not null end,
    'deadline', case when g.status = 'invite' then g.created_at + interval '2 minutes'
                     when g.status = 'playing' then g.end_at end,
    'now', now(), 'created_at', g.created_at, 'msg', g.msg, 'reply', g.reply,
    'ended_at', case when g.status = 'done' then g.move_at end,
    'opp', (select jsonb_build_object('pid', o.pid, 'name', o.name, 'avatar', o.avatar,
                                      'online', coalesce(o.seen_at > now() - interval '75 seconds', false))
              from public.rc_players o where o.device = case when g.p1 = p_device then g.p2 else g.p1 end)) $function$;

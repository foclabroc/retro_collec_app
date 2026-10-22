CREATE OR REPLACE FUNCTION public.rc__bs_json(g rc_bs, p_device text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with s as (select case when g.p1 = p_device then 1 else 2 end as side)
  select jsonb_build_object(
    'id', g.id, 'mode', g.mode, 'phase', g.status,
    'status', case when g.status = 'setup' then 'playing' else g.status end,
    'turn', case when g.status = 'setup' then
                   case when (case when s.side = 1 then g.fleet1 else g.fleet2 end) is null then s.side else 3 - s.side end
                 else g.turn end,
    'side', s.side,
    'my_fleet', case when s.side = 1 then g.fleet1 else g.fleet2 end,
    'opp_ready', (case when s.side = 1 then g.fleet2 else g.fleet1 end) is not null,
    'my_shots', case when s.side = 1 then g.shots1 else g.shots2 end,
    'opp_shots', case when s.side = 1 then g.shots2 else g.shots1 end,
    'opp_sunk', case when g.status = 'done' then coalesce(case when s.side = 1 then g.fleet2 else g.fleet1 end, '[]'::jsonb)
                     else public.rc__bs_sunk(case when s.side = 1 then g.fleet2 else g.fleet1 end, case when s.side = 1 then g.shots1 else g.shots2 end) end,
    'winner', g.winner, 'reason', g.reason, 'stake', g.stake, 'paid', g.paid,
    'friendly', case when g.stake = 0 and g.status <> 'done' then public.rc__duel_why(g.p1, g.p2) end, 'moves', g.moves,
    'last_cell', g.last_cell, 'last_by', case when g.last_by is null then null when g.last_by = s.side then 'me' else 'opp' end,
    'deadline', case when g.status = 'invite' then g.created_at + public.rc__bs_limit(g.mode, 'invite')
                     when g.status in ('setup', 'playing') then g.move_at + public.rc__bs_limit(g.mode, g.status) end,
    'now', now(), 'created_at', g.created_at, 'msg', g.msg, 'reply', g.reply, 'ended_at', case when g.status = 'done' then g.move_at end,
    'emo_opp', case when s.side = 1 then g.emo2 else g.emo1 end,
    'emo_opp_at', case when s.side = 1 then g.emo2_at else g.emo1_at end,
    'opp', (select jsonb_build_object('pid', o.pid, 'name', o.name, 'avatar', o.avatar,
                                      'online', coalesce(o.seen_at > now() - interval '75 seconds', false))
              from public.rc_players o where o.device = case when s.side = 1 then g.p2 else g.p1 end))
  from s $function$

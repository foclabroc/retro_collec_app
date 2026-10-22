CREATE OR REPLACE FUNCTION public.rc__c4_json(g rc_c4, p_device text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select jsonb_build_object(
    'id', g.id, 'mode', g.mode, 'status', g.status, 'board', g.board, 'turn', g.turn,
    'side', case when g.p1 = p_device then 1 else 2 end,
    'winner', g.winner, 'reason', g.reason, 'stake', g.stake, 'paid', g.paid,
    'friendly', case when g.stake = 0 and g.status <> 'done' then public.rc__duel_why(g.p1, g.p2) end, 'moves', g.moves, 'last_col', g.last_col,
    'deadline', case when g.status = 'invite' then g.created_at + public.rc__c4_invite_limit(g.mode)
                     when g.status = 'playing' then g.move_at + public.rc__c4_limit(g.mode) end,
    'now', now(), 'created_at', g.created_at, 'msg', g.msg, 'reply', g.reply, 'ended_at', case when g.status = 'done' then g.move_at end,
    'emo_opp', case when g.p1 = p_device then g.emo2 else g.emo1 end,
    'emo_opp_at', case when g.p1 = p_device then g.emo2_at else g.emo1_at end,
    'opp', (select jsonb_build_object('pid', o.pid, 'name', o.name, 'avatar', o.avatar,
                                      'online', coalesce(o.seen_at > now() - interval '75 seconds', false))
              from public.rc_players o where o.device = case when g.p1 = p_device then g.p2 else g.p1 end)) $function$

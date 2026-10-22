create or replace function public.rc__tour_json(p_tid bigint, p_device text, p_full boolean)
 returns jsonb
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select jsonb_build_object(
    'id', t.id, 'name', t.name, 'game', t.game, 'size', t.size, 'start_at', t.start_at,
    'fee', t.fee, 'split', t.split, 'lots', t.lots, 'status', t.status, 'round', t.round, 'rounds', t.rounds,
    'pot', case when t.status = 'open' then (select coalesce(sum(paid), 0) from public.rc_tour_players where tid = t.id) else t.pot end,
    'n', (select count(*) from public.rc_tour_players where tid = t.id),
    'mine', exists (select 1 from public.rc_tour_players where tid = t.id and device = p_device),
    'winner', public.rc__pinfo(t.winner), 'second', public.rc__pinfo(t.second),
    'ended_at', t.ended_at, 'now', now())
  || case when not p_full then '{}'::jsonb else jsonb_build_object(
    'players', (select coalesce(jsonb_agg(public.rc__pinfo(tp.device) || jsonb_build_object('place', tp.place) order by tp.at), '[]'::jsonb)
                  from public.rc_tour_players tp where tp.tid = t.id),
    'matches', (select coalesce(jsonb_agg(jsonb_build_object(
                   'id', m.id, 'round', m.round, 'slot', m.slot, 'best', m.best, 'w1', m.w1, 'w2', m.w2,
                   'status', m.status, 'reason', m.reason, 'game_id', m.game_id,
                   'start_at', m.start_at, 'deadline', m.start_at + interval '3 minutes',
                   'ready1', m.ready1 is not null, 'ready2', m.ready2 is not null,
                   'p1', public.rc__pinfo(m.p1), 'p2', public.rc__pinfo(m.p2),
                   'winner', (select pid from public.rc_players where device = m.winner),
                   'mine', p_device in (m.p1, m.p2)) order by m.round, m.slot), '[]'::jsonb)
                  from public.rc_tour_matches m where m.tid = t.id),
    'me', (select pid from public.rc_players where device = p_device)) end
  from public.rc_tour t where t.id = p_tid $function$;

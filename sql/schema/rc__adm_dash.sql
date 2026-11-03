create or replace function public.rc__adm_dash()
 returns jsonb language sql stable security definer set search_path to 'public', 'extensions'
as $$
  select jsonb_build_object(
    'players',  (select count(*) from rc_players),
    'online',   (select count(*) from rc_players where seen_at > now() - interval '75 seconds'),
    'today',    (select count(*) from rc_players where (seen_at at time zone 'Europe/Paris')::date = rc__today()),
    'yesterday',(select coalesce(players, 0) from rc_daily where day = rc__today() - 1),
    'new7',     (select count(*) from rc_players where created_at > now() - interval '7 days'),
    'packs24',  (select count(*) from rc_pack_log where at > now() - interval '24 hours'),
    'packs48',  (select count(*) from rc_pack_log where at > now() - interval '48 hours' and at <= now() - interval '24 hours'),
    'made24',   (select coalesce(sum(coins), 0) from rc_activity where coins > 0 and at > now() - interval '24 hours'),
    'burnt24',  (select coalesce(-sum(coins), 0) from rc_activity where coins < 0 and at > now() - interval '24 hours'),
    'live',     coalesce(jsonb_array_length(rc_live_games()), 0),
    'duels_today', (select count(*) from (select status, reason, move_at from rc_c4 union all select status, reason, move_at from rc_bs
                                          union all select status, reason, move_at from rc_rj) d
                     where d.status = 'done' and coalesce(d.reason, '') not in ('declined', 'cancelled', 'expired')
                       and (d.move_at at time zone 'Europe/Paris')::date = rc__today()),
    'days', coalesce((select jsonb_agg(jsonb_build_object('day', d.day::date, 'players', coalesce(x.players, 0), 'packs', coalesce(x.packs, 0)) order by d.day)
                        from generate_series(rc__today() - 13, rc__today(), interval '1 day') d(day)
                        left join rc_daily x on x.day = d.day::date), '[]'::jsonb),
    'versions', coalesce((select jsonb_agg(jsonb_build_object('ver', v, 'os', o, 'n', n) order by v desc, n desc)
                            from (select coalesce(app_ver, '?') v, coalesce(app_os, '?') o, count(*) n from rc_players
                                   where seen_at > now() - interval '7 days' group by 1, 2) s), '[]'::jsonb),
    'config', (select jsonb_object_agg(key, value) from rc_config),
    'events', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'icon', icon, 'title', title, 'kind', kind, 'starts_at', starts_at, 'ends_at', ends_at) order by starts_at)
                          from rc_events where active and (ends_at is null or ends_at > now()) and starts_at < now() + interval '14 days'), '[]'::jsonb),
    'tours', coalesce((select jsonb_agg(jsonb_build_object('id', t.id, 'name', t.name, 'game', t.game, 'start_at', t.start_at, 'size', t.size, 'status', t.status,
                                                          'n', (select count(*) from rc_tour_players p where p.tid = t.id)) order by t.start_at)
                         from rc_tour t where t.status in ('open', 'running')), '[]'::jsonb),
    'alerts', rc__adm_alerts(),
    'admin_log', coalesce((select jsonb_agg(jsonb_build_object('at', l.at, 'action', l.action) order by l.id desc)
                             from (select * from rc_admin_log order by id desc limit 5) l), '[]'::jsonb)
  );
$$;

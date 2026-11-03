create or replace function public.rc__adm_cfg()
 returns jsonb language sql stable security definer set search_path to 'public' as $$
  select jsonb_build_object(
    'live', coalesce((select value from rc_config where key = 'live'), '{}'::jsonb),
    'wpool', (select jsonb_agg(jsonb_build_object('id', p.id, 'kind', p.kind, 'goal', p.goal, 'reward', p.reward,
                                                  'off', coalesce((select (e->>'off')::boolean from jsonb_array_elements(coalesce((select value from rc_config where key = 'wpool'), '[]'::jsonb)) e
                                                                     where (e->>'id')::int = p.id limit 1), false)) order by p.id) from rc__wpool() p),
    'week', rc__week(), 'wsel', to_jsonb(rc__wsel()),
    'week_done', (select jsonb_agg(jsonb_build_object('i', i, 'n', (select count(*) from rc_players where w_week = rc__week() and coalesce(w_prog[i], 0) >= (rc__wgoals())[i])))
                    from generate_series(1, 6) i),
    'express', coalesce((select value from rc_config where key = 'express'),
                        '[{"kind":"open","goal":2,"reward":{"coins":80}},{"kind":"gift","goal":1,"reward":{"coins":60}},{"kind":"trade","goal":1,"reward":{"coins":100}},{"kind":"win","goal":1,"reward":{"coins":100}},{"kind":"gamedle","goal":1,"reward":{"coins":60}},{"kind":"play","goal":2,"reward":{"coins":80}},{"kind":"new","goal":2,"reward":{"coins":80}},{"kind":"quiz","goal":5,"reward":{"coins":60}},{"kind":"sale","goal":1,"reward":{"coins":80}},{"kind":"free","goal":1,"reward":{"coins":50}},{"kind":"premium","goal":1,"reward":{"coins":100}},{"kind":"epic","goal":1,"reward":{"coins":150,"pixels":1}}]'::jsonb),
    'express_today', (select jsonb_build_object('kind', d.kind, 'goal', d.goal, 'reward', d.reward,
                                                'n', (select count(*) from rc_express x where x.day = rc__today()),
                                                'done', (select count(*) from rc_express x where x.day = rc__today() and x.prog >= x.goal),
                                                'claimed', (select count(*) from rc_express x where x.day = rc__today() and x.claimed))
                        from rc__express_def(rc__today()) d),
    'wheel', jsonb_build_object('w', to_jsonb(rc__wheel_w('w', array[22, 15, 12, 19, 8, 14, 4, 3, 3])),
                                'wg', to_jsonb(rc__wheel_w('wg', array[19, 15, 14, 17, 10, 12, 6, 3, 4])),
                                'spins7', (select count(*) from rc_activity where kind = 'wheel' and at > now() - interval '7 days')),
    'solo_prize', jsonb_build_object('1', rc__rj_solo_prize(1), '2', rc__rj_solo_prize(2), '3', rc__rj_solo_prize(3)),
    'alerts', coalesce((select value from rc_config where key = 'alerts'), '{}'::jsonb),
    'trophies', (select jsonb_agg(jsonb_build_object('kind', t.kind, 't', jsonb_build_array(t.t1, t.t2, t.t3),
                                                     'n', (select jsonb_object_agg(g.tier, g.n) from (select tier, count(*) n from rc_trophy_got x where x.kind = t.kind group by tier) g))
                                  order by t.ord) from rc__tpool() t),
    'gifts', (select jsonb_agg(jsonb_build_object('ver', g.ver, 'reward', g.reward, 'out_at', g.out_at,
                                                  'got', (select count(*) from rc_upgrade_got u where u.ver = g.ver),
                                                  'can', (select count(*) from rc_players p where p.created_at < g.out_at)) order by g.ver desc) from rc_upgrade_gifts g),
    'houses', (select jsonb_object_agg(h, n) from (select coalesce(house, '0') h, count(*) n from rc_players group by 1) x),
    'pioche_today', (select count(*) from rc_players where pick_day = rc__today()),
    'quiz7', (select jsonb_build_object('n', count(*), 'players', count(distinct device), 'coins', coalesce(sum(coins), 0)) from rc_activity where kind = 'quiz' and at > now() - interval '7 days')
  )
$$;

create or replace function public.rc__adm_econ(p_days int)
 returns jsonb language plpgsql stable security definer set search_path to 'public', 'extensions'
as $$
declare v_days int := least(greatest(coalesce(p_days, 7), 1), 30); since timestamptz; t date := rc__today();
begin
  since := (t - (v_days - 1))::timestamp at time zone 'Europe/Paris';
  return jsonb_build_object(
    'days', v_days,
    'sources', coalesce((select jsonb_agg(jsonb_build_object('kind', kind, 'n', s) order by s desc)
                           from (select kind, sum(coins) s from rc_activity where coins > 0 and at >= since group by kind) x), '[]'::jsonb),
    'sinks', coalesce((select jsonb_agg(jsonb_build_object('kind', kind, 'n', s) order by s desc)
                         from (select kind, -sum(coins) s from rc_activity where coins < 0 and at >= since group by kind) x), '[]'::jsonb),
    'pixels', jsonb_build_object('made', (select coalesce(sum(pixels), 0) from rc_activity where pixels > 0 and at >= since),
                                 'spent', (select coalesce(-sum(pixels), 0) from rc_activity where pixels < 0 and at >= since)),
    'per_day', coalesce((select jsonb_agg(jsonb_build_object('day', d.day::date, 'made', coalesce(x.made, 0), 'burnt', coalesce(x.burnt, 0),
                                                             'signups', coalesce(y.n, 0)) order by d.day)
                           from generate_series(t - (v_days - 1), t, interval '1 day') d(day)
                           left join (select (at at time zone 'Europe/Paris')::date dd, sum(coins) filter (where coins > 0) made, -sum(coins) filter (where coins < 0) burnt
                                        from rc_activity where at >= since group by 1) x on x.dd = d.day::date
                           left join (select (created_at at time zone 'Europe/Paris')::date dd, count(*) n from rc_players group by 1) y on y.dd = d.day::date), '[]'::jsonb),
    'packs_day', coalesce((select jsonb_agg(jsonb_build_object('day', dd, 'kind', kind, 'n', c))
                             from (select (at at time zone 'Europe/Paris')::date dd, kind, count(*) c from rc_pack_log where at >= since group by 1, 2) x), '[]'::jsonb),
    'packs_kind', coalesce((select jsonb_agg(jsonb_build_object('kind', kind, 'n', c) order by c desc)
                              from (select kind, count(*) c from rc_pack_log where at >= since group by kind) x), '[]'::jsonb),
    'heat', coalesce((select jsonb_agg(jsonb_build_array(dw, h, c))
                        from (select extract(isodow from at at time zone 'Europe/Paris')::int - 1 dw, extract(hour from at at time zone 'Europe/Paris')::int h,
                                     count(distinct device) c from rc_activity where at >= since group by 1, 2) x), '[]'::jsonb),
    'wealth', (select jsonb_build_object('total', sum(coins), 'avg', round(avg(coins)), 'median', percentile_cont(0.5) within group (order by coins),
                                         'top1', (select sum(coins) from (select coins from rc_players order by coins desc limit greatest(1, (select count(*) from rc_players) / 100)) a),
                                         'top10', (select sum(coins) from (select coins from rc_players order by coins desc limit greatest(1, (select count(*) from rc_players) / 10)) a),
                                         'frag', sum(coalesce(fragments, 0)), 'pixels', sum(pixels))
                 from rc_players),
    'tops', jsonb_build_object(
      'packs', coalesce((select jsonb_agg(jsonb_build_object('pid', p.pid, 'name', p.name, 'n', x.n) order by x.n desc)
                           from (select device, count(*) n from rc_pack_log where at >= since group by device order by 2 desc limit 5) x join rc_players p on p.device = x.device), '[]'::jsonb),
      'gain', coalesce((select jsonb_agg(jsonb_build_object('pid', p.pid, 'name', p.name, 'n', x.n) order by x.n desc)
                          from (select device, sum(coins) n from rc_activity where coins > 0 and at >= since group by device order by 2 desc limit 5) x join rc_players p on p.device = x.device), '[]'::jsonb),
      'wins', coalesce((select jsonb_agg(jsonb_build_object('pid', p.pid, 'name', p.name, 'n', x.n) order by x.n desc)
                          from (select d, count(*) n from (
                                  select case when winner = 1 then p1 else p2 end d, move_at from rc_c4 where status = 'done' and winner in (1, 2)
                                  union all select case when winner = 1 then p1 else p2 end, move_at from rc_bs where status = 'done' and winner in (1, 2)
                                  union all select case when winner = 1 then p1 else p2 end, move_at from rc_rj where status = 'done' and winner in (1, 2)) w
                                 where move_at >= since group by d order by 2 desc limit 5) x join rc_players p on p.device = x.d), '[]'::jsonb),
      'market', coalesce((select jsonb_agg(jsonb_build_object('pid', p.pid, 'name', p.name, 'n', x.n) order by x.n desc)
                            from (select d, sum(price) n from (select seller d, price, sold_at from rc_market where buyer is not null
                                                               union all select buyer, price, sold_at from rc_market where buyer is not null) m
                                   where sold_at >= since group by d order by 2 desc limit 5) x join rc_players p on p.device = x.d), '[]'::jsonb),
      'gifts', coalesce((select jsonb_agg(jsonb_build_object('pid', p.pid, 'name', p.name, 'n', x.n) order by x.n desc)
                           from (select giver, count(*) n from rc_gifts where giver is not null and created_at >= since group by giver order by 2 desc limit 5) x
                           join rc_players p on p.device = x.giver), '[]'::jsonb),
      'cards', coalesce((select jsonb_agg(jsonb_build_object('pid', pid, 'name', name, 'n', cards) order by cards desc)
                           from (select pid, name, cards from rc_players order by cards desc limit 5) x), '[]'::jsonb)),
    'market', jsonb_build_object(
      'sales', (select count(*) from rc_market where buyer is not null and sold_at >= since),
      'volume', (select coalesce(sum(price), 0) from rc_market where buyer is not null and sold_at >= since),
      'open', (select count(*) from rc_market where buyer is null),
      'trades_ok', (select count(*) from rc_trades where status = 'accepted' and done_at >= since),
      'trades', (select count(*) from rc_trades where created_at >= since),
      'prices', coalesce((select jsonb_agg(jsonb_build_object('r', r, 'f', f, 'avg', a, 'n', c))
                            from (select c.rarity r, m.finish f, round(avg(m.price)) a, count(*) c from rc_market m join rc_cards c on c.id = m.card
                                   where m.buyer is not null and m.sold_at > now() - interval '30 days' group by 1, 2) x), '[]'::jsonb)),
    'games', coalesce((select jsonb_agg(jsonb_build_object('game', g, 'n', c, 'players', pl))
                         from (select g, count(*) c, count(distinct p) pl from (
                                 select 'c4' g, p1 p, move_at from rc_c4 where status = 'done' and coalesce(reason, '') not in ('declined', 'cancelled', 'expired')
                                 union all select 'bs', p1, move_at from rc_bs where status = 'done' and coalesce(reason, '') not in ('declined', 'cancelled', 'expired')
                                 union all select case when kind = 'run' then 'rn' else 'rj' end, p1, move_at from rc_rj where status = 'done' and coalesce(reason, '') not in ('declined', 'cancelled', 'expired')) x
                                where move_at >= since group by g) s), '[]'::jsonb),
    'compl', coalesce((select jsonb_agg(jsonb_build_object('sys', sys, 'avg', a, 'full', f) order by a desc)
                         from (select c.sys, round(100.0 * count(o.*) / nullif((select count(*) from rc_cards c2 where c2.sys = c.sys), 0)
                                                   / nullif((select count(*) from rc_players where packs > 0), 0), 1) a, 0 f
                                 from rc_cards c left join (select distinct device, card from rc_owned where finish < 3) o on o.card = c.id
                                group by c.sys) s), '[]'::jsonb),
    'most', coalesce((select jsonb_agg(jsonb_build_object('card', card, 'title', title, 'sys', sys, 'n', n) order by n desc)
                        from (select o.card, c.title, c.sys, count(distinct o.device) n from rc_owned o join rc_cards c on c.id = o.card
                               group by 1, 2, 3 order by 4 desc limit 8) x), '[]'::jsonb),
    'never', (select count(*) from rc_cards c where not exists (select 1 from rc_owned o where o.card = c.id)),
    'never_list', coalesce((select jsonb_agg(jsonb_build_object('card', id, 'title', title, 'sys', sys, 'r', rarity) order by rarity desc, sys)
                              from (select * from rc_cards c where not exists (select 1 from rc_owned o where o.card = c.id)
                                     order by rarity desc limit 60) x), '[]'::jsonb)
  );
end $$;

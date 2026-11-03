create or replace function public.rc__adm_player(p_pid text)
 returns jsonb language plpgsql stable security definer set search_path to 'public', 'extensions'
as $$
declare v rc_players; t date := rc__today(); v_ip text;
begin
  select * into v from rc_players where pid = p_pid;
  if v.device is null then raise exception 'joueur inconnu'; end if;
  select ip into v_ip from rc_ip_log where kind = 'signup' and name = v.name_key order by at limit 1;
  return jsonb_build_object(
    'pid', v.pid, 'name', v.name, 'avatar', v.avatar, 'score', v.score, 'cards', v.cards, 'packs', v.packs,
    'coins', v.coins, 'pixels', v.pixels, 'frag', coalesce(v.fragments, 0), 'lots', coalesce(v.lots, 0),
    'created_at', v.created_at, 'seen_at', v.seen_at, 'online', v.seen_at > now() - interval '75 seconds',
    'ver', v.app_ver, 'os', v.app_os, 'ver_at', v.app_at, 'days', coalesce(v.days, 0), 'streak', coalesce(v.streak, 0),
    'blocked', coalesce(v.blocked, false), 'pass', v.pass_hash is not null, 'house', v.house, 'cab_game', v.cab_game,
    'showcase', v.showcase, 'trophies_show', v.trophies,
    'rank', (select count(*) + 1 from rc_players o where o.score > v.score),
    'referrer', (select s.name from rc_players s where s.device = v.referrer),
    'muted_until', (select max(coalesce(b.until, 'infinity')) from rc_chat_bans b where b.device = v.device and (b.until is null or b.until > now())),
    'login_fails', (select count(*) from rc_ip_log where kind = 'login_fail' and name = v.name_key and at > now() - interval '24 hours'),
    'note', (select jsonb_build_object('note', n.note, 'tags', n.tags, 'at', n.at) from rc_admin_notes n where n.device = v.device),
    'stock', (select count(*) from rc_card_stock s where s.device = v.device and s.taken_at is null),
    'trophies', coalesce((select jsonb_object_agg(tier, n) from (select tier, count(*) n from rc_trophy_got where device = v.device group by tier) x), '{}'::jsonb),
    -- paquets par type
    'packs_by', coalesce((select jsonb_agg(jsonb_build_object('kind', kind, 'today', d1, 'week', d7, 'total', n) order by n desc)
                           from (select kind, count(*) n,
                                        count(*) filter (where (at at time zone 'Europe/Paris')::date = t) d1,
                                        count(*) filter (where at > now() - interval '7 days') d7
                                   from rc_pack_log where device = v.device group by kind) s), '[]'::jsonb),
    -- activité par jour (30 j)
    'daily', coalesce((select jsonb_agg(jsonb_build_object('day', d.day::date, 'n', coalesce(x.n, 0), 'packs', coalesce(y.n, 0)) order by d.day)
                         from generate_series(t - 29, t, interval '1 day') d(day)
                         left join (select (at at time zone 'Europe/Paris')::date dd, count(*) n from rc_activity where device = v.device group by 1) x on x.dd = d.day::date
                         left join (select (at at time zone 'Europe/Paris')::date dd, count(*) n from rc_pack_log where device = v.device group by 1) y on y.dd = d.day::date), '[]'::jsonb),
    -- heures de jeu (30 j) : jour de semaine 0-6 × heure
    'hours', coalesce((select jsonb_agg(jsonb_build_array(dw, h, n))
                         from (select extract(isodow from at at time zone 'Europe/Paris')::int - 1 dw,
                                      extract(hour from at at time zone 'Europe/Paris')::int h, count(*) n
                                 from rc_activity where device = v.device group by 1, 2) s), '[]'::jsonb),
    -- économie 7 j : par type d'action
    'eco7', coalesce((select jsonb_agg(jsonb_build_object('kind', kind, 'plus', plus, 'minus', minus, 'px', px) order by plus + minus desc)
                        from (select kind, coalesce(sum(coins) filter (where coins > 0), 0) plus, coalesce(-sum(coins) filter (where coins < 0), 0) minus,
                                     coalesce(sum(pixels), 0) px
                                from rc_activity where device = v.device and at > now() - interval '7 days' group by kind) s
                       where plus + minus <> 0 or px <> 0), '[]'::jsonb),
    -- solde de pièces reconstitué sur 30 j (à partir du solde actuel, en remontant)
    'balance30', coalesce((select jsonb_agg(jsonb_build_object('day', s.dd, 'coins', v.coins - coalesce(s.after, 0)) order by s.dd)
                             from (select d.day::date as dd,
                                          (select sum(coins) from rc_activity a where a.device = v.device
                                             and (a.at at time zone 'Europe/Paris')::date > d.day::date) after
                                     from generate_series(t - 29, t, interval '1 day') d(day)) s), '[]'::jsonb),
    -- cartes : rareté × finition
    'cards_by', coalesce((select jsonb_agg(jsonb_build_object('r', r, 'f', f, 'n', n, 'q', q))
                            from (select c.rarity r, o.finish f, count(*) n, sum(o.qty) q
                                    from rc_owned o join rc_cards c on c.id = o.card where o.device = v.device group by 1, 2) s), '[]'::jsonb),
    'pk', (select count(distinct card) from rc_owned where device = v.device and card like 'pk\_%'),
    -- complétion par console / saga
    'compl', coalesce((select jsonb_agg(jsonb_build_object('sys', sys, 'have', have, 'total', total) order by have::numeric / total desc)
                         from (select c.sys, count(distinct o.card) filter (where o.device is not null) have, count(distinct c.id) total
                                 from rc_cards c left join rc_owned o on o.card = c.id and o.device = v.device and o.finish < 3
                                group by c.sys) s), '[]'::jsonb),
    -- partenaires (cadeaux, échanges, ventes)
    'partners', coalesce((select jsonb_agg(jsonb_build_object('pid', p.pid, 'name', p.name, 'avatar', p.avatar, 'g_out', g_out, 'g_in', g_in,
                                                              'trades', tr, 'sales', sa, 'same_ip', p.name_key in
                                                                (select name from rc_ip_log where kind = 'signup' and ip = v_ip))
                                             order by g_out + g_in + tr + sa desc)
                            from (select o, sum(g_out) g_out, sum(g_in) g_in, sum(tr) tr, sum(sa) sa from (
                                    select receiver o, 1 g_out, 0 g_in, 0 tr, 0 sa from rc_gifts where giver = v.device
                                    union all select giver, 0, 1, 0, 0 from rc_gifts where receiver = v.device and giver is not null
                                    union all select case when sender = v.device then receiver else sender end, 0, 0, 1, 0
                                                from rc_trades where status = 'accepted' and v.device in (sender, receiver)
                                    union all select case when seller = v.device then buyer else seller end, 0, 0, 0, 1
                                                from rc_market where buyer is not null and v.device in (seller, buyer)) z
                                   group by o order by sum(g_out + g_in + tr + sa) desc limit 12) s
                            join rc_players p on p.device = s.o), '[]'::jsonb),
    'market', jsonb_build_object(
      'sales', (select count(*) from rc_market where seller = v.device and buyer is not null),
      'buys', (select count(*) from rc_market where buyer = v.device),
      'earned', (select coalesce(sum(price), 0) from rc_market where seller = v.device and buyer is not null),
      'spent', (select coalesce(sum(price), 0) from rc_market where buyer = v.device),
      'open', (select count(*) from rc_market where seller = v.device and buyer is null)),
    'chat', jsonb_build_object(
      'week', (select count(*) from rc_chat where device = v.device and created_at > now() - interval '7 days'),
      'hidden', (select count(*) from rc_chat where device = v.device and hidden),
      'reports', (select coalesce(sum(reports), 0) from rc_chat where device = v.device)),
    -- jeux : victoires / défaites / nuls
    'games', coalesce((select jsonb_agg(jsonb_build_object('game', g, 'w', w, 'l', l, 'd', dr)) from (
                         select g, count(*) filter (where me = winner) w, count(*) filter (where winner in (1, 2) and me <> winner) l,
                                count(*) filter (where winner = 0) dr
                           from (select 'c4' g, case when p1 = v.device then 1 else 2 end me, winner from rc_c4 where status = 'done' and v.device in (p1, p2)
                                 union all select 'bs', case when p1 = v.device then 1 else 2 end, winner from rc_bs where status = 'done' and v.device in (p1, p2)
                                 union all select case when kind = 'run' then 'rn' else 'rj' end, case when p1 = v.device then 1 else 2 end, winner
                                             from rc_rj where status = 'done' and v.device in (p1, p2)) x group by g) s), '[]'::jsonb),
    'tours', jsonb_build_object(
      'played', (select count(*) from rc_tour_players where device = v.device),
      'won', (select count(*) from rc_tour_players where device = v.device and place = 1)),
    -- comptes créés depuis la même IP
    'linked', coalesce((select jsonb_agg(jsonb_build_object('pid', p.pid, 'name', p.name, 'avatar', p.avatar))
                          from rc_players p where v_ip is not null and p.device <> v.device
                           and p.name_key in (select name from rc_ip_log where kind = 'signup' and ip = v_ip)), '[]'::jsonb),
    'recent', coalesce((select jsonb_agg(jsonb_build_object('at', a.at, 'kind', a.kind, 'txt', a.txt, 'c', a.coins, 'p', a.pixels,
                                                            'other', (select o.name from rc_players o where o.device = a.other)) order by a.id desc)
                          from (select * from rc_activity where device = v.device order by id desc limit 40) a), '[]'::jsonb)
  );
end $$;

-- Outil admin web (admin.html) : étape 1
-- Une seule porte d'entrée pour les nouvelles fonctions : rc_admin_x(device, sig, op, args)
--   signature : '<device>|admin|x|<op>|<args>'  (args = texte JSON, '{}' si rien)
-- Lectures : dash, players, player, econ, catalog
-- Actions  : balance, card, password, clearfail, note, mute
-- Relançable.

-- ── Notes privées sur les joueurs ─────────────────────────────────────────
create table if not exists public.rc_admin_notes (
  device text primary key references public.rc_players(device) on delete cascade,
  note   text not null default '',
  tags   text not null default '',
  at     timestamptz not null default now()
);
alter table public.rc_admin_notes owner to rc_owner;
revoke all on public.rc_admin_notes from anon, authenticated;

-- ── Alertes calculées (seuils fixes pour l'instant) ───────────────────────
create or replace function public.rc__adm_alerts()
 returns jsonb language sql stable security definer set search_path to 'public', 'extensions'
as $$
  select coalesce(jsonb_agg(a), '[]'::jsonb) from (
    -- gros gain en 24 h
    select jsonb_build_object('kind', 'gain', 'level', 'hi', 'pid', p.pid, 'name', p.name, 'n', g.n) a
      from (select device, sum(coins) n from rc_activity
             where coins > 0 and at > now() - interval '24 hours' and kind not in ('sold') group by device having sum(coins) >= 15000) g
      join rc_players p on p.device = g.device
    union all
    -- plusieurs comptes créés depuis la même IP en 7 jours
    select jsonb_build_object('kind', 'ip', 'level', 'hi', 'names', s.names, 'n', s.n)
      from (select ip, count(distinct name) n, jsonb_agg(distinct name) names from rc_ip_log
             where kind = 'signup' and at > now() - interval '7 days' group by ip having count(distinct name) >= 2) s
    union all
    -- cadeaux en boucle (même donneur → même receveur, 48 h)
    select jsonb_build_object('kind', 'gifts', 'level', 'md', 'from', a.name, 'to', b.name, 'from_pid', a.pid, 'n', g.n)
      from (select giver, receiver, count(*) n from rc_gifts
             where giver is not null and created_at > now() - interval '48 hours' group by 1, 2 having count(*) >= 8) g
      join rc_players a on a.device = g.giver join rc_players b on b.device = g.receiver
    union all
    -- vente très en dessous du prix moyen (24 h)
    select jsonb_build_object('kind', 'cheap', 'level', 'md', 'id', m.id, 'card', m.card, 'f', m.finish, 'price', m.price, 'avg', m.avg,
                              'seller', s.name, 'buyer', b.name, 'seller_pid', s.pid)
      from (select x.*, rc__avg_price(x.card, x.finish, x.id) avg from rc_market x
             where x.buyer is not null and x.sold_at > now() - interval '24 hours') m
      join rc_players s on s.device = m.seller join rc_players b on b.device = m.buyer
     where m.avg >= 100 and m.price * 10 < m.avg
    union all
    -- erreurs de connexion (24 h)
    select jsonb_build_object('kind', 'login', 'level', 'lo', 'name', l.name, 'n', l.n,
                              'pid', (select pid from rc_players where name_key = l.name))
      from (select name, count(*) n from rc_ip_log where kind = 'login_fail' and at > now() - interval '24 hours'
             group by name having count(*) >= 5) l
  ) x;
$$;
alter function public.rc__adm_alerts() owner to rc_owner;

-- ── Tableau de bord ───────────────────────────────────────────────────────
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
alter function public.rc__adm_dash() owner to rc_owner;

-- ── Liste des joueurs (tous, avec de quoi trier) ──────────────────────────
create or replace function public.rc__adm_players()
 returns jsonb language sql stable security definer set search_path to 'public', 'extensions'
as $$
  with act as (
    select device,
           sum(coins) filter (where coins > 0 and at > now() - interval '24 hours') gain24,
           sum(coins) filter (where at > now() - interval '24 hours') net24,
           -sum(coins) filter (where coins < 0 and at > now() - interval '7 days') spent7
      from rc_activity where at > now() - interval '7 days' group by device),
  duels as (
    select d, count(*) w from (
      select case when winner = 1 then p1 else p2 end d from rc_c4 where status = 'done' and winner in (1, 2)
      union all select case when winner = 1 then p1 else p2 end from rc_bs where status = 'done' and winner in (1, 2)
      union all select case when winner = 1 then p1 else p2 end from rc_rj where status = 'done' and winner in (1, 2)) x group by d),
  mk as (
    select d, sum(price) v from (select seller d, price from rc_market where buyer is not null
                                 union all select buyer, price from rc_market where buyer is not null) x group by d),
  pk as (select device, count(*) filter (where at > now() - interval '24 hours') p24 from rc_pack_log group by device)
  select coalesce(jsonb_agg(jsonb_build_object(
           'pid', p.pid, 'name', p.name, 'avatar', p.avatar, 'score', p.score, 'cards', p.cards, 'packs', p.packs,
           'packs24', coalesce(pk.p24, 0),
           'coins', p.coins, 'pixels', p.pixels, 'frag', coalesce(p.fragments, 0),
           'gain24', coalesce(act.gain24, 0), 'net24', coalesce(act.net24, 0), 'spent7', coalesce(act.spent7, 0),
           'wins', coalesce(duels.w, 0), 'market', coalesce(mk.v, 0), 'days', coalesce(p.days, 0), 'streak', coalesce(p.streak, 0),
           'seen_at', p.seen_at, 'created_at', p.created_at, 'ver', p.app_ver, 'os', p.app_os,
           'online', p.seen_at > now() - interval '75 seconds',
           'blocked', coalesce(p.blocked, false), 'admin', exists (select 1 from rc_admins a where a.pid = p.pid),
           'muted', exists (select 1 from rc_chat_bans b where b.device = p.device and (b.until is null or b.until > now())),
           'pass', p.pass_hash is not null,
           'note', exists (select 1 from rc_admin_notes n where n.device = p.device and n.note <> ''))
           order by p.seen_at desc nulls last), '[]'::jsonb)
    from rc_players p
    left join act on act.device = p.device
    left join duels on duels.d = p.device
    left join mk on mk.d = p.device
    left join pk on pk.device = p.device;
$$;
alter function public.rc__adm_players() owner to rc_owner;

-- ── Fiche complète d'un joueur ────────────────────────────────────────────
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
alter function public.rc__adm_player(text) owner to rc_owner;

-- ── Statistiques globales sur N jours ─────────────────────────────────────
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
alter function public.rc__adm_econ(int) owner to rc_owner;

-- ── Point d'entrée unique ─────────────────────────────────────────────────
create or replace function public.rc_admin_x(p_device text, p_sig text, p_op text, p_args text)
 returns jsonb language plpgsql security definer set search_path to 'public', 'extensions'
as $$
declare j jsonb; d text; v rc_players; n int; f int; c text; pw text; mode text;
begin
  perform public.rc__admin(p_device, p_sig, 'x|' || coalesce(p_op, '') || '|' || coalesce(p_args, ''));
  j := coalesce(nullif(p_args, ''), '{}')::jsonb;
  if p_op in ('player', 'balance', 'card', 'password', 'clearfail', 'note', 'mute') then
    select * into v from rc_players where pid = j->>'pid';
    if v.device is null then raise exception 'joueur inconnu'; end if;
    d := v.device;
  end if;
  -- journal : seulement les actions
  if p_op in ('balance', 'card', 'password', 'clearfail', 'note', 'mute') then
    insert into rc_admin_log (device, action)
    values (p_device, left('x|' || p_op || '|' || coalesce(v.name, '') || '|' || coalesce(p_args, ''), 400));
  end if;

  case p_op
  when 'dash' then return rc__adm_dash();
  when 'players' then return rc__adm_players();
  when 'player' then return rc__adm_player(j->>'pid');
  when 'econ' then return rc__adm_econ((j->>'days')::int);
  when 'catalog' then
    return coalesce((select jsonb_agg(jsonb_build_array(id, sys, rarity, title)) from rc_cards), '[]'::jsonb);

  when 'balance' then
    -- {pid, mode: add|set, coins, pixels, frag, why}
    mode := coalesce(j->>'mode', 'add');
    if mode = 'set' then
      update rc_players set coins = greatest(coalesce((j->>'coins')::bigint, coins), 0),
                            pixels = greatest(coalesce((j->>'pixels')::int, pixels), 0),
                            fragments = greatest(coalesce((j->>'frag')::int, fragments, 0), 0)
       where device = d;
    else
      update rc_players set coins = greatest(coins + coalesce((j->>'coins')::bigint, 0), 0),
                            pixels = greatest(pixels + coalesce((j->>'pixels')::int, 0), 0),
                            fragments = greatest(coalesce(fragments, 0) + coalesce((j->>'frag')::int, 0), 0)
       where device = d;
    end if;
    select * into v from rc_players where device = d;
    return jsonb_build_object('coins', v.coins, 'pixels', v.pixels, 'frag', v.fragments);

  when 'card' then
    -- {pid, card, f, n}  n > 0 : donner, n < 0 : retirer
    c := j->>'card'; f := coalesce((j->>'f')::int, 0); n := coalesce((j->>'n')::int, 1);
    if not exists (select 1 from rc_cards where id = c) then raise exception 'carte inconnue'; end if;
    if f not between 0 and 3 or n = 0 or abs(n) > 50 then raise exception 'valeurs invalides'; end if;
    if n > 0 then
      insert into rc_owned (device, card, finish, qty, first_at) values (d, c, f, n, now())
      on conflict (device, card, finish) do update set qty = rc_owned.qty + excluded.qty;
    else
      update rc_owned set qty = qty + n where device = d and card = c and finish = f and qty + n > 0;
      if not found then delete from rc_owned where device = d and card = c and finish = f; end if;
    end if;
    perform rc__rescore(d);
    return jsonb_build_object('qty', coalesce((select qty from rc_owned where device = d and card = c and finish = f), 0));

  when 'password' then
    -- nouveau mot de passe provisoire (8 caractères), renvoyé une seule fois
    pw := substr(translate(encode(gen_random_bytes(9), 'base64'), '+/=lIO0', 'xyzkmPQ'), 1, 8);
    update rc_players set pass_hash = crypt(encode(digest('pt-pass#41c9|' || pw, 'sha256'), 'hex'), gen_salt('bf', 8)),
                          pass_fail = 0, pass_lock = null
     where device = d;
    delete from rc_ip_log where kind = 'login_fail' and name = v.name_key;
    return jsonb_build_object('password', pw);

  when 'clearfail' then
    delete from rc_ip_log where kind = 'login_fail' and name = v.name_key;
    update rc_players set pass_fail = 0, pass_lock = null where device = d;
    return jsonb_build_object('ok', true);

  when 'note' then
    insert into rc_admin_notes (device, note, tags, at) values (d, left(coalesce(j->>'note', ''), 4000), left(coalesce(j->>'tags', ''), 400), now())
    on conflict (device) do update set note = excluded.note, tags = excluded.tags, at = now();
    return jsonb_build_object('ok', true);

  when 'mute' then
    -- {pid, hours}  0 = lever, -1 = définitif
    n := coalesce((j->>'hours')::int, 24);
    delete from rc_chat_bans where device = d;
    if n <> 0 then
      insert into rc_chat_bans (device, until) values (d, case when n < 0 then null else now() + make_interval(hours => n) end);
    end if;
    return jsonb_build_object('ok', true);

  else
    raise exception 'opération inconnue : %', p_op;
  end case;
end $$;
alter function public.rc_admin_x(text, text, text, text) owner to rc_owner;
grant execute on function public.rc_admin_x(text, text, text, text) to anon;

notify pgrst, 'reload schema';

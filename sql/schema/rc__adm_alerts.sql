create or replace function public.rc__adm_alerts()
 returns jsonb language sql stable security definer set search_path to 'public', 'extensions'
as $$
  with c as (select coalesce((select value from rc_config where key = 'alerts'), '{}'::jsonb) j),
  t as (select coalesce((j->>'gain')::int, 15000) gain, coalesce((j->>'ip')::int, 2) ip, coalesce((j->>'gifts')::int, 8) gifts,
               coalesce((j->>'cheap')::int, 10) cheap, coalesce((j->>'login')::int, 5) login from c)
  select coalesce(jsonb_agg(a), '[]'::jsonb) from (
    select jsonb_build_object('key', 'gain:' || p.pid || ':' || rc__today(), 'kind', 'gain', 'level', 'hi', 'pid', p.pid, 'name', p.name, 'n', g.n) a
      from (select device, sum(coins) n from rc_activity
             where coins > 0 and at > now() - interval '24 hours' and kind not in ('sold') group by device having sum(coins) >= (select gain from t)) g
      join rc_players p on p.device = g.device
    union all
    select jsonb_build_object('key', 'ip:' || s.ip, 'kind', 'ip', 'level', 'hi', 'names', s.names, 'n', s.n)
      from (select ip, count(distinct name) n, jsonb_agg(distinct name) names from rc_ip_log
             where kind = 'signup' and at > now() - interval '7 days' group by ip having count(distinct name) >= (select ip from t)) s
    union all
    select jsonb_build_object('key', 'gifts:' || a.pid || ':' || b.pid, 'kind', 'gifts', 'level', 'md', 'from', a.name, 'to', b.name, 'from_pid', a.pid, 'n', g.n)
      from (select giver, receiver, count(*) n from rc_gifts
             where giver is not null and created_at > now() - interval '48 hours' group by 1, 2 having count(*) >= (select gifts from t)) g
      join rc_players a on a.device = g.giver join rc_players b on b.device = g.receiver
    union all
    select jsonb_build_object('key', 'cheap:' || m.id, 'kind', 'cheap', 'level', 'md', 'id', m.id, 'card', m.card, 'f', m.finish, 'price', m.price, 'avg', m.avg,
                              'seller', s.name, 'buyer', b.name, 'seller_pid', s.pid)
      from (select x.*, rc__avg_price(x.card, x.finish, x.id) avg from rc_market x
             where x.buyer is not null and x.sold_at > now() - interval '24 hours') m
      join rc_players s on s.device = m.seller join rc_players b on b.device = m.buyer
     where m.avg >= 100 and m.price * 100 < m.avg * (select cheap from t)
    union all
    select jsonb_build_object('key', 'login:' || l.name || ':' || rc__today(), 'kind', 'login', 'level', 'lo', 'name', l.name, 'n', l.n,
                              'pid', (select pid from rc_players where name_key = l.name))
      from (select name, count(*) n from rc_ip_log where kind = 'login_fail' and at > now() - interval '24 hours'
             group by name having count(*) >= (select login from t)) l
  ) x where not exists (select 1 from rc_admin_alert_ok k where k.key = x.a->>'key');
$$;

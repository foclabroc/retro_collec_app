create or replace function public.rc__adm_cheat()
 returns jsonb language sql stable security definer set search_path to 'public' as $$
  -- groupes de comptes créés depuis la même IP (toutes dates), avec ce qu'ils se sont passé
  select coalesce(jsonb_agg(g order by (g->>'flow')::int desc, (g->>'n')::int desc), '[]'::jsonb) from (
    select jsonb_build_object('key', 'ip:' || s.ip, 'ip', left(s.ip, 8), 'n', count(*), 'ok', exists (select 1 from rc_admin_alert_ok k where k.key = 'ip:' || s.ip),
             'players', jsonb_agg(jsonb_build_object('pid', p.pid, 'name', p.name, 'avatar', p.avatar, 'created_at', p.created_at, 'coins', p.coins,
                                                     'packs', p.packs, 'cards', p.cards, 'blocked', p.blocked, 'seen_at', p.seen_at) order by p.created_at),
             'gifts', (select count(*) from rc_gifts x where x.giver = any(array_agg(p.device)) and x.receiver = any(array_agg(p.device))),
             'sales', (select count(*) from rc_market x where x.buyer is not null and x.seller = any(array_agg(p.device)) and x.buyer = any(array_agg(p.device))),
             'sales_v', (select coalesce(sum(price), 0) from rc_market x where x.buyer is not null and x.seller = any(array_agg(p.device)) and x.buyer = any(array_agg(p.device))),
             'trades', (select count(*) from rc_trades x where x.status = 'accepted' and x.sender = any(array_agg(p.device)) and x.receiver = any(array_agg(p.device))),
             'flow', (select count(*) from rc_gifts x where x.giver = any(array_agg(p.device)) and x.receiver = any(array_agg(p.device)))
                   + (select count(*) from rc_market x where x.buyer is not null and x.seller = any(array_agg(p.device)) and x.buyer = any(array_agg(p.device)))
                   + (select count(*) from rc_trades x where x.status = 'accepted' and x.sender = any(array_agg(p.device)) and x.receiver = any(array_agg(p.device)))) g
      from (select distinct ip, name from rc_ip_log where kind = 'signup') s
      join rc_players p on p.name_key = s.name
     group by s.ip having count(*) >= 2) z
$$;

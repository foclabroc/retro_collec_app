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

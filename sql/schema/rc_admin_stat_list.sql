create or replace function public.rc_admin_stat_list(p_device text, p_sig text, p_kind text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare today date := public.rc__today();
begin
  perform public.rc__admin(p_device, p_sig, 'statlist|' || coalesce(p_kind, ''));
  if p_kind in ('active7', 'today') then
    return coalesce((select jsonb_agg(jsonb_build_object('pid', p.pid, 'name', p.name, 'avatar', p.avatar, 'at', p.seen_at,
                                                         'n', p.packs, 'coins', p.coins, 'ver', p.app_ver, 'os', p.app_os) order by p.seen_at desc)
                       from public.rc_players p
                      where (p_kind = 'active7' and p.seen_at > now() - interval '7 days')
                         or (p_kind = 'today' and (p.seen_at at time zone 'Europe/Paris')::date = today)), '[]'::jsonb);
  elsif p_kind = 'new7' then
    return coalesce((select jsonb_agg(jsonb_build_object('pid', p.pid, 'name', p.name, 'avatar', p.avatar, 'at', p.created_at,
                                                         'n', p.packs, 'ref', (select s.name from public.rc_players s where s.device = p.referrer))
                                      order by p.created_at desc)
                       from public.rc_players p where p.created_at > now() - interval '7 days'), '[]'::jsonb);
  elsif p_kind = 'packs' then
    return coalesce((select jsonb_agg(jsonb_build_object('pid', p.pid, 'name', p.name, 'avatar', p.avatar, 'at', x.last,
                                                         'n', x.n, 'kinds', x.kinds) order by x.n desc, x.last desc)
                       from (select l.device, count(*)::int n, max(l.at) last, jsonb_object_agg(l.kind, l.c) kinds
                               from (select device, coalesce(kind, '?') kind, count(*)::int c, max(at) at from public.rc_pack_log
                                      where (at at time zone 'Europe/Paris')::date = today group by device, coalesce(kind, '?')) l
                              group by l.device) x
                       join public.rc_players p on p.device = x.device), '[]'::jsonb);
  elsif p_kind = 'sales' then
    return coalesce((select jsonb_agg(jsonb_build_object('pid', s.pid, 'name', s.name, 'avatar', s.avatar, 'at', m.sold_at,
                                                         'other', b.name, 'other_pid', b.pid, 'card', m.card, 'f', m.finish, 'price', m.price)
                                      order by m.sold_at desc)
                       from public.rc_market m
                       join public.rc_players s on s.device = m.seller
                       left join public.rc_players b on b.device = m.buyer
                      where m.buyer is not null and (m.sold_at at time zone 'Europe/Paris')::date = today), '[]'::jsonb);
  elsif p_kind = 'duels' then
    return coalesce((select jsonb_agg(jsonb_build_object('pid', a.pid, 'name', a.name, 'avatar', a.avatar, 'at', d.move_at,
                                                         'other', b.name, 'other_pid', b.pid, 'game', d.jeu, 'winner', d.winner, 'reason', d.reason)
                                      order by d.move_at desc)
                       from (select 'c4' jeu, p1, p2, status, reason, winner, move_at from public.rc_c4
                             union all select 'bs', p1, p2, status, reason, winner, move_at from public.rc_bs) d
                       join public.rc_players a on a.device = d.p1
                       left join public.rc_players b on b.device = d.p2
                      where d.status = 'done' and coalesce(d.reason, '') not in ('declined', 'cancelled', 'expired')
                        and (d.move_at at time zone 'Europe/Paris')::date = today), '[]'::jsonb);
  end if;
  raise exception 'liste inconnue';
end $function$;
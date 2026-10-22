create or replace function public.rc_admin_player(p_device text, p_sig text, p_pid text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare v public.rc_players;
begin
  perform public.rc__admin(p_device, p_sig, 'player|' || coalesce(p_pid, ''));
  select * into v from public.rc_players where pid = p_pid;
  if v.device is null then raise exception 'joueur inconnu'; end if;
  return jsonb_build_object(
    'pid', v.pid, 'name', v.name, 'avatar', v.avatar, 'created_at', v.created_at, 'seen_at', v.seen_at,
    'coins', v.coins, 'pixels', v.pixels, 'packs', v.packs, 'cards', v.cards, 'score', v.score, 'days', v.days, 'blocked', v.blocked,
    'ver', v.app_ver, 'os', v.app_os, 'ver_at', v.app_at,
    'referrer', (select s.name from public.rc_players s where s.device = v.referrer),
    'events', coalesce((select jsonb_agg(e order by e->>'at' desc) from (
      select e from (
        select jsonb_build_object('at', coalesce(m.sold_at, m.created_at), 'kind', case when m.seller = v.device then (case when m.buyer is null then 'listing' else 'sold' end) else 'bought' end,
                 'other', (select o.name from public.rc_players o where o.device = case when m.seller = v.device then m.buyer else m.seller end),
                 'card', m.card, 'f', m.finish, 'price', m.price,
                 'avg', public.rc__avg_price(m.card, m.finish, m.id)) e
          from public.rc_market m where v.device in (m.seller, m.buyer)
        union all
        select jsonb_build_object('at', coalesce(t.done_at, t.created_at), 'kind', 'trade', 'status', t.status,
                 'other', (select o.name from public.rc_players o where o.device = case when t.sender = v.device then t.receiver else t.sender end),
                 'gave', case when t.sender = v.device then t.give else t.want end,
                 'got', case when t.sender = v.device then t.want else t.give end,
                 'gave_v', public.rc__items_value(case when t.sender = v.device then t.give else t.want end),
                 'got_v', public.rc__items_value(case when t.sender = v.device then t.want else t.give end))
          from public.rc_trades t where v.device in (t.sender, t.receiver)
        union all
        select jsonb_build_object('at', g.created_at, 'kind', case when g.giver = v.device then 'gift_out' else 'gift_in' end,
                 'other', coalesce((select o.name from public.rc_players o where o.device = case when g.giver = v.device then g.receiver else g.giver end), g.giver_name))
          from public.rc_gifts g where v.device in (g.giver, g.receiver)
        union all
        select jsonb_build_object('at', x.created_at, 'kind', 'duel', 'game', x.jeu, 'status', x.status, 'reason', x.reason,
                 'other', (select o.name from public.rc_players o where o.device = case when x.p1 = v.device then x.p2 else x.p1 end),
                 'result', case when x.winner = 0 then 'draw' when x.winner is null then null
                                when (x.winner = 1) = (x.p1 = v.device) then 'win' else 'loss' end)
          from (select 'c4' jeu, p1, p2, status, reason, winner, created_at from public.rc_c4
                union all select 'bs', p1, p2, status, reason, winner, created_at from public.rc_bs) x
         where v.device in (x.p1, x.p2)
        union all
        select jsonb_build_object('at', c.created_at, 'kind', 'chat', 'msg', c.msg, 'hidden', c.hidden, 'reports', c.reports)
          from public.rc_chat c where c.device = v.device
        union all
        select jsonb_build_object('at', l.at, 'kind', 'pack', 'pack', l.kind, 'sys', l.sys)
          from public.rc_pack_log l where l.device = v.device
      ) all_e order by e->>'at' desc limit 100) s), '[]'::jsonb));
end $function$;
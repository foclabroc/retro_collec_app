-- ═══════════════════════════════════════════════════════════════════════════
-- Pixel Trade : version de l'appli de chaque joueur, visible dans l'admin. Relançable.
--  · rc_players.app_ver / app_os / app_at : dernière version vue, appareil (web, android…), date.
--  · rc_upgrade_gift (appelée à chaque démarrage) les remplit ; p_ver = « 1.0.21|android » depuis
--    le 22/10 au soir (avant : « 1.0.21 » seul, appareil inconnu). Même signature SQL : rien à recharger.
--  · Admin : 'ver', 'os', 'ver_at' dans rc_admin_accounts, rc_admin_player, rc_admin_stat_list (today / active7).
-- Lancement : psql -U postgres -d postgres -f 2026-10-22_version_joueurs.sql
-- ═══════════════════════════════════════════════════════════════════════════
begin;

alter table public.rc_players add column if not exists app_ver text;
alter table public.rc_players add column if not exists app_os text;
alter table public.rc_players add column if not exists app_at timestamptz;

create or replace function public.rc_upgrade_gift(p_device text, p_ver text, p_sig text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare
  v_rw jsonb; v_out timestamptz; v_ver text;
begin
  perform public.rc__check(p_sig, p_device || '|upgrade|' || p_ver);
  if not exists (select 1 from public.rc_players where device = p_device) then raise exception 'joueur inconnu'; end if;
  -- version de l'appli (vue par l'admin) : p_ver = « 1.0.21|android » (version seule pour les anciennes appli)
  update public.rc_players
     set app_ver = left(split_part(coalesce(p_ver, ''), '|', 1), 20),
         app_os = nullif(left(split_part(coalesce(p_ver, ''), '|', 2), 12), ''),
         app_at = now()
   where device = p_device;
  v_ver := split_part(coalesce(p_ver, ''), '|', 1);
  -- cadeau par version (même JSON que les récompenses → rc__grant) + date de sortie de la version :
  -- seuls les comptes créés avant la sortie le reçoivent (un nouveau compte ne peut pas réclamer les anciens)
  select x.rw, x.out_at into v_rw, v_out from (values
    ('1.0.16', '{"coins":500}'::jsonb, timestamptz '2026-10-21 09:30+00'),
    ('1.0.18', '{"coins":600,"pixels":8,"packs":{"premium":1}}'::jsonb, timestamptz '2026-10-22 06:45+00')
  ) x(ver, rw, out_at) where x.ver = v_ver;
  if v_rw is null then return jsonb_build_object('coins', 0); end if;
  if exists (select 1 from public.rc_players where device = p_device and created_at >= v_out) then
    return jsonb_build_object('coins', 0);
  end if;
  insert into public.rc_upgrade_got (device, ver) values (p_device, v_ver) on conflict do nothing;
  if not found then return jsonb_build_object('coins', 0); end if;
  perform public.rc__grant(p_device, v_rw);
  return jsonb_build_object('coins', coalesce((v_rw->>'coins')::int, 0), 'reward', v_rw);
end $function$;

CREATE OR REPLACE FUNCTION public.rc_admin_accounts(p_device text, p_sig text, p_query text DEFAULT ''::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  perform public.rc__admin(p_device, p_sig, 'accounts|' || coalesce(p_query, ''));
  return coalesce((
    select jsonb_agg(x order by (x->>'created_at') desc) from (
      select jsonb_build_object(
        'pid', p.pid, 'name', p.name, 'avatar', p.avatar, 'created_at', p.created_at, 'seen_at', p.seen_at,
        'coins', p.coins, 'pixels', p.pixels, 'packs', p.packs, 'cards', p.cards, 'score', p.score,
        'age_h', floor(extract(epoch from now() - p.created_at) / 3600)::int,
        'gifts_out', (select count(*) from public.rc_gifts g where g.giver = p.device),
        'gifts_top', (select count(*) from public.rc_gifts g where g.giver = p.device group by g.receiver order by count(*) desc limit 1),
        'gifts_top_name', (select r.name from public.rc_gifts g join public.rc_players r on r.device = g.receiver
                            where g.giver = p.device group by r.name order by count(*) desc limit 1),
        'gifts_in', (select count(*) from public.rc_gifts g where g.receiver = p.device and g.giver is not null),
        'sales', (select count(*) from public.rc_market m where m.seller = p.device and m.buyer is not null),
        'buys', (select count(*) from public.rc_market m where m.buyer = p.device),
        'trades', (select count(*) from public.rc_trades t where t.status = 'accepted' and p.device in (t.sender, t.receiver)),
        -- valeur des cartes données et reçues dans les échanges acceptés
        'trade_given', (select coalesce(sum(public.rc__items_value(case when t.sender = p.device then t.give else t.want end)), 0)
                          from public.rc_trades t where t.status = 'accepted' and p.device in (t.sender, t.receiver)),
        'trade_got', (select coalesce(sum(public.rc__items_value(case when t.sender = p.device then t.want else t.give end)), 0)
                        from public.rc_trades t where t.status = 'accepted' and p.device in (t.sender, t.receiver)),
        -- achats payés beaucoup plus cher que le prix moyen (pièces transférées en douce)
        'overpaid', (select count(*) from public.rc_market m
                      where m.buyer = p.device and m.price >= 100
                        and m.price > 5 * coalesce(public.rc__avg_price(m.card, m.finish, m.id), m.price)),
        'blocked', p.blocked, 'ver', p.app_ver, 'os', p.app_os, 'ver_at', p.app_at,
        'chat_banned', exists (select 1 from public.rc_chat_bans b where b.device = p.device and (b.until is null or b.until > now()))
      ) as x
        from public.rc_players p
       where (coalesce(p_query, '') = '' and p.created_at > now() - interval '7 days')
          or (coalesce(p_query, '') <> '' and p.name_key like public.rc__name_key(p_query) || '%')
       order by p.created_at desc limit 80) s), '[]'::jsonb);
end $function$;

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

commit;

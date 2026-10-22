-- 2026-10-22 : @tous dans le chat, réservé aux admins (rc_admins) : compte comme une mention pour tous les joueurs
-- (pastille, toast, notification Android). Un @tous écrit par un joueur normal ne notifie personne. Relançable.

create or replace function public.rc_notifs(p_device text)
 returns jsonb
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select jsonb_build_object(
    'trades', (select count(*)::int from public.rc_trades t where t.receiver = p_device and t.status = 'pending'),
    'sales', coalesce((
      select jsonb_agg(jsonb_build_object('id', m.id, 'card', m.card, 'f', m.finish, 'price', m.price,
                                          'buyer', (select b.name from public.rc_players b where b.device = m.buyer))
                       order by m.sold_at)
        from public.rc_market m, public.rc_players me
       where me.device = p_device and m.seller = p_device and m.buyer is not null and m.sold_at > me.market_seen), '[]'::jsonb),
    'wheel', (select wheel_day is distinct from public.rc__today() from public.rc_players where device = p_device),
    'gifts', (select count(*)::int from public.rc_gifts g where g.receiver = p_device and g.opened_at is null),
    'gift_from', (select g.giver_name from public.rc_gifts g where g.receiver = p_device and g.opened_at is null order by g.id desc limit 1),
    'gift_last', (select coalesce(max(g.id), 0) from public.rc_gifts g where g.receiver = p_device),
    'gifts_left', (select 3 - case when gift_day = public.rc__today() then gift_n else 0 end from public.rc_players where device = p_device),
    'can_gift', (select gift_day is distinct from public.rc__today() or gift_n < 3 from public.rc_players where device = p_device),
    'week', coalesce(public.rc__wk_ready(p_device), 0),
    'trophies', coalesce(public.rc__tro_ready(p_device), 0),
    'reacts', coalesce(public.rc__reacts_new(p_device), 0),
    'lots', (select lots from public.rc_players where device = p_device),
    'free', public.rc__free_in(p_device) = 0,
    'free_in', public.rc__free_in(p_device),
    'free_at', (select coalesce(extract(epoch from last_free_at)::bigint, 0) from public.rc_players where device = p_device),
    'lot_free', (select public.rc__lot_day() and lot_free is distinct from public.rc__today() from public.rc_players where device = p_device),
    'lot_price', public.rc__lot_price(),
    'chat', (select count(*)::int from public.rc_chat c, public.rc_players me
              where me.device = p_device and c.id > me.chat_seen and c.device <> p_device and not c.hidden),
    'chat_last', (select coalesce(max(c.id), 0) from public.rc_chat c where not c.hidden),
    'mention', (select coalesce(max(c.id), 0) from public.rc_chat c, public.rc_players me
                 where me.device = p_device and c.id > me.chat_seen and c.device <> p_device and not c.hidden
                   and (lower(regexp_replace(c.msg, '[^[:alnum:]@]', '', 'g')) like '%@' || me.name_key || '%'
                        or (lower(c.msg) ~ '@tous\M' and public.rc__is_admin(c.device))))) $function$;

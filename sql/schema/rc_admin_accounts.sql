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
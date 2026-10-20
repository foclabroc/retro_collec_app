CREATE OR REPLACE FUNCTION public.rc_admin_links(p_device text, p_sig text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  perform public.rc__admin(p_device, p_sig, 'links');
  return coalesce((
    with flows as (
      select giver a, receiver b, 1 gifts, 0 cardv, 0 coins, 0 overpay, 0 trades, 0 sales
        from public.rc_gifts where giver is not null and created_at > now() - interval '14 days'
      union all
      select sender, receiver, 0, public.rc__items_value(give), 0, 0, 1, 0
        from public.rc_trades where status = 'accepted' and done_at > now() - interval '14 days'
      union all
      select receiver, sender, 0, public.rc__items_value(want), 0, 0, 0, 0
        from public.rc_trades where status = 'accepted' and done_at > now() - interval '14 days'
      union all
      select m.seller, m.buyer, 0, public.rc__recycle_value(c.rarity, m.finish), 0, 0, 0, 1
        from public.rc_market m join public.rc_cards c on c.id = m.card
       where m.buyer is not null and m.sold_at > now() - interval '14 days'
      union all
      select m.buyer, m.seller, 0, 0, m.price,
             greatest(0, m.price - coalesce(public.rc__avg_price(m.card, m.finish, m.id), m.price)), 0, 0
        from public.rc_market m
       where m.buyer is not null and m.sold_at > now() - interval '14 days'),
    f as (select a, b, sum(gifts)::int g, sum(cardv)::int cv, sum(coins)::int co, sum(overpay)::int ov, sum(trades)::int tr, sum(sales)::int sa
            from flows group by a, b),
    pairs as (
      select least(f.a, f.b) x, greatest(f.a, f.b) y,
             sum(case when f.a < f.b then f.g else 0 end)::int g_xy, sum(case when f.a > f.b then f.g else 0 end)::int g_yx,
             sum(case when f.a < f.b then f.cv else 0 end)::int cv_xy, sum(case when f.a > f.b then f.cv else 0 end)::int cv_yx,
             sum(case when f.a < f.b then f.co else 0 end)::int co_xy, sum(case when f.a > f.b then f.co else 0 end)::int co_yx,
             sum(case when f.a < f.b then f.ov else 0 end)::int ov_xy, sum(case when f.a > f.b then f.ov else 0 end)::int ov_yx,
             sum(f.tr)::int trades, sum(f.sa)::int sales
        from f group by 1, 2),
    scored as (
      select p.*, px.name nx, py.name ny, px.pid pidx, py.pid pidy, px.avatar avx, py.avatar avy,
             floor(extract(epoch from now() - px.created_at) / 3600)::int agex,
             floor(extract(epoch from now() - py.created_at) / 3600)::int agey,
             (abs((p.cv_xy + p.co_xy) - (p.cv_yx + p.co_yx)) + p.ov_xy + p.ov_yx + 15 * (p.g_xy + p.g_yx))
               * case when least(px.created_at, py.created_at) > now() - interval '3 days'
                        or greatest(px.created_at, py.created_at) > now() - interval '3 days' then 2 else 1 end as score
        from pairs p join public.rc_players px on px.device = p.x join public.rc_players py on py.device = p.y)
    select jsonb_agg(jsonb_build_object(
             'a', nx, 'b', ny, 'pid_a', pidx, 'pid_b', pidy, 'av_a', avx, 'av_b', avy, 'age_a', agex, 'age_b', agey,
             'gifts_ab', g_xy, 'gifts_ba', g_yx, 'cards_ab', cv_xy, 'cards_ba', cv_yx, 'coins_ab', co_xy, 'coins_ba', co_yx,
             'over_ab', ov_xy, 'over_ba', ov_yx, 'trades', trades, 'sales', sales, 'score', score) order by score desc)
      from (select * from scored order by score desc limit 40) s), '[]'::jsonb);
end $function$

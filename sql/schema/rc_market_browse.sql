CREATE OR REPLACE FUNCTION public.rc_market_browse(p_device text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(jsonb_agg(x order by (x->>'last_at') desc), '[]'::jsonb) from (
    select jsonb_build_object(
             'card', g.card, 'finish', g.finish, 'lots', g.lots, 'min_price', g.min_price, 'last_at', g.last_at,
             'seller', (select p.name from public.rc_market m2 join public.rc_players p on p.device = m2.seller
                         where m2.card = g.card and m2.finish = g.finish and m2.buyer is null and m2.seller <> p_device
                         order by m2.price, m2.created_at limit 1),
             'avg', (select round(avg(s.price))::int from public.rc_market s
                      where s.card = g.card and s.finish = g.finish and s.buyer is not null and s.sold_at > now() - interval '30 days')) as x
      from (select m.card, m.finish, count(*)::int as lots, min(m.price)::int as min_price, max(m.created_at) as last_at
              from public.rc_market m
             where m.buyer is null and m.seller <> p_device
             group by m.card, m.finish
             order by max(m.created_at) desc
             limit 1500) g) t $function$

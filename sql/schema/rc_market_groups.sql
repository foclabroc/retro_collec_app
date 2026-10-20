CREATE OR REPLACE FUNCTION public.rc_market_groups(p_device text, p_sys text, p_missing boolean)
 RETURNS TABLE(card text, finish smallint, lots integer, min_price integer, last_at timestamp with time zone, seller text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select m.card, m.finish, count(*)::int, min(m.price)::int, max(m.created_at),
         (select p.name from public.rc_market m2 join public.rc_players p on p.device = m2.seller
           where m2.card = m.card and m2.finish = m.finish and m2.buyer is null and m2.seller <> p_device
           order by m2.price, m2.created_at limit 1)
    from public.rc_market m
    join public.rc_cards c on c.id = m.card
   where m.buyer is null and m.seller <> p_device
     and (p_sys is null or p_sys = '' or c.sys = p_sys)
     and (not coalesce(p_missing, false)
          or not exists (select 1 from public.rc_owned o where o.device = p_device and o.card = m.card))
   group by m.card, m.finish
   order by max(m.created_at) desc
   limit 300 $function$

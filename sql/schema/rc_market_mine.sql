CREATE OR REPLACE FUNCTION public.rc_market_mine(p_device text)
 RETURNS TABLE(id bigint, card text, finish smallint, price integer, sold boolean, buyer text, created_at timestamp with time zone, sold_at timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select m.id, m.card, m.finish, m.price, m.buyer is not null,
         (select b.name from public.rc_players b where b.device = m.buyer), m.created_at, m.sold_at
    from public.rc_market m
   where m.seller = p_device and (m.buyer is null or m.sold_at > now() - interval '7 days')
   order by m.buyer is not null, m.created_at desc $function$

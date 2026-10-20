CREATE OR REPLACE FUNCTION public.rc_market_list(p_device text, p_sys text, p_card text, p_missing boolean)
 RETURNS TABLE(id bigint, card text, finish smallint, price integer, seller text, seller_pid text, created_at timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select m.id, m.card, m.finish, m.price, p.name, p.pid, m.created_at
    from public.rc_market m
    join public.rc_players p on p.device = m.seller
    join public.rc_cards c on c.id = m.card
   where m.buyer is null and m.seller <> p_device
     and (p_sys is null or p_sys = '' or c.sys = p_sys)
     and (p_card is null or p_card = '' or m.card = p_card)
     and (not coalesce(p_missing, false)
          or not exists (select 1 from public.rc_owned o where o.device = p_device and o.card = m.card))
   order by m.created_at desc
   limit 100 $function$

CREATE OR REPLACE FUNCTION public.rc_market_price(p_card text, p_finish integer)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select jsonb_build_object(
    'avg',    (select round(avg(price))::int from public.rc_market
                where card = p_card and finish = p_finish and buyer is not null and sold_at > now() - interval '30 days'),
    'sold',   (select count(*)::int from public.rc_market
                where card = p_card and finish = p_finish and buyer is not null and sold_at > now() - interval '30 days'),
    'min',    (select min(price) from public.rc_market where card = p_card and finish = p_finish and buyer is null),
    'open',   (select count(*)::int from public.rc_market where card = p_card and finish = p_finish and buyer is null)) $function$

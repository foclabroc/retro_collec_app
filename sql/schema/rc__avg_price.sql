CREATE OR REPLACE FUNCTION public.rc__avg_price(p_card text, p_finish integer, p_except bigint)
 RETURNS integer
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select round(avg(price))::int from public.rc_market
   where card = p_card and finish = p_finish and buyer is not null and id <> coalesce(p_except, 0)
     and sold_at > now() - interval '30 days' $function$

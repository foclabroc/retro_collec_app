CREATE OR REPLACE FUNCTION public.rc__gamedle_card(p_day date)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  select id from public.rc_cards
   where saga is null and rarity >= case when p_day >= date '2026-10-17' then 3 else 2 end
   order by md5(id || p_day::text) limit 1 $function$

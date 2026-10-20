create or replace function public.rc__lot_price()
 returns integer
 language sql
 stable
as $function$ select 500 * (100 - public.rc__promo('lot')) / 100 $function$;

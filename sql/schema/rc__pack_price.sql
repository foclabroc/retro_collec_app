create or replace function public.rc__pack_price(k text)
 returns integer
 language sql
 stable
as $function$
  select (case k when 'free' then 0 when 'mixte' then public.rc__cfg('mixte', 100)::int when 'console' then public.rc__cfg('console', 150)::int
                 when 'premium' then public.rc__cfg('premium', 400)::int
                 when 'mystery' then public.rc__cfg('mystery', 120)::int when 'gift' then 0 when 'lot' then 0 end)
         * (100 - public.rc__promo(k)) / 100 $function$;

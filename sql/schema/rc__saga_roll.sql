CREATE OR REPLACE FUNCTION public.rc__saga_roll()
 RETURNS text
 LANGUAGE sql
AS $function$
  select case when random() < public.rc__cfg('saga', 3.2) / 100 then (select id from public.rc_cards where saga is not null order by random() limit 1) end $function$

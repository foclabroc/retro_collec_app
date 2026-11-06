CREATE OR REPLACE FUNCTION public.rc__saga_roll()
 RETURNS text
 LANGUAGE sql
AS $function$
  select case
    when random() < public.rc__cfg('pk', 0.15) / 100 then (select id from public.rc_cards where saga = 'pk' order by random() limit 1)
    when random() < public.rc__cfg('da', 0.15) / 100 then (select id from public.rc_cards where saga = 'da' order by random() limit 1)
    when random() < public.rc__cfg('db', 0.15) / 100 then (select id from public.rc_cards where saga = 'db' order by random() limit 1)
    when random() < public.rc__cfg('saga', 3.2) / 100 then (select id from public.rc_cards where saga is not null and saga not in ('pk', 'da', 'db') order by random() limit 1)
  end $function$


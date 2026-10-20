CREATE OR REPLACE FUNCTION public.rc__give(p_dev text, p_card text, p_f integer, p_n integer)
 RETURNS void
 LANGUAGE sql
AS $function$
  insert into public.rc_owned (device, card, finish, qty) values (p_dev, p_card, p_f, p_n)
  on conflict (device, card, finish) do update set qty = public.rc_owned.qty + excluded.qty $function$

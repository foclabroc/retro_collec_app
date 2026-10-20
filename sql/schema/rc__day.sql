CREATE OR REPLACE FUNCTION public.rc__day(p_dev text)
 RETURNS void
 LANGUAGE sql
AS $function$
  update public.rc_players set day = public.rc__today(), d_open = 0, d_recycle = 0, d_trade = 0, d_done = 0
   where device = p_dev and day is distinct from public.rc__today() $function$

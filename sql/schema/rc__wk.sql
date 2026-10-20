CREATE OR REPLACE FUNCTION public.rc__wk(p_dev text)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  update public.rc_players set w_week = public.rc__week(), w_prog = '{0,0,0,0,0,0}', w_claim = 0
   where device = p_dev and w_week is distinct from public.rc__week() $function$

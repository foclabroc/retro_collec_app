CREATE OR REPLACE FUNCTION public.rc_quiz_status(p_device text)
 RETURNS integer
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select greatest(0, 100 - case when quiz_day = public.rc__today() then quiz_gain else 0 end)
    from public.rc_players where device = p_device $function$

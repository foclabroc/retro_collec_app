CREATE OR REPLACE FUNCTION public.rc_gamedle_state(p_device text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select public.rc__gamedle_json(p_device) $function$

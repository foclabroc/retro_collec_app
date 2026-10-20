CREATE OR REPLACE FUNCTION public.rc_has_password(p_device text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce((select pass_hash is not null from public.rc_players where device = p_device), false) $function$

CREATE OR REPLACE FUNCTION public.rc__is_admin(p_dev text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (select 1 from public.rc_admins a join public.rc_players p on p.pid = a.pid where p.device = p_dev) $function$

CREATE OR REPLACE FUNCTION public.rc__cfg(p_sub text, p_def numeric)
 RETURNS numeric
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce((select (value->>p_sub)::numeric from public.rc_config where key = 'live'), p_def) $function$

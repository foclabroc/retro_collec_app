CREATE OR REPLACE FUNCTION public.rc__free_in(p_dev text)
 RETURNS integer
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce((select greatest(0, ceil(extract(epoch from (
            last_free_at + make_interval(hours => coalesce(public.rc__effect('free_fast'), 6)) - now()))))::int
                     from public.rc_players where device = p_dev), 0) $function$

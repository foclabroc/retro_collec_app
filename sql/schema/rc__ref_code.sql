CREATE OR REPLACE FUNCTION public.rc__ref_code(p_pid text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$ select 'PT-' || upper(left(p_pid, 6)) $function$

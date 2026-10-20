CREATE OR REPLACE FUNCTION public.rc__wgoals()
 RETURNS integer[]
 LANGUAGE sql
 IMMUTABLE
AS $function$ select array[10, 30, 3, 2, 3, 1] $function$

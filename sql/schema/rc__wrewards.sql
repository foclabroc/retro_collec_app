CREATE OR REPLACE FUNCTION public.rc__wrewards()
 RETURNS integer[]
 LANGUAGE sql
 IMMUTABLE
AS $function$ select array[150, 100, 200, 200, 100, 150] $function$

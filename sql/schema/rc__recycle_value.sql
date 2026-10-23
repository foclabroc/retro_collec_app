CREATE OR REPLACE FUNCTION public.rc__recycle_value(r integer, f integer)
 RETURNS integer
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select (array[2, 5, 20, 60, 200])[r + 1] * (array[1, 3, 10, 30])[least(greatest(f, 0), 3) + 1] $function$

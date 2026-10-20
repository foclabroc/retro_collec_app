CREATE OR REPLACE FUNCTION public.rc__pts(r integer)
 RETURNS integer
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select (array[1, 2, 5, 15, 50])[r + 1] $function$

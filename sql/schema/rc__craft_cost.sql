CREATE OR REPLACE FUNCTION public.rc__craft_cost(r integer)
 RETURNS integer
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select (array[50, 150, 500, 1500, 5000])[r + 1] $function$

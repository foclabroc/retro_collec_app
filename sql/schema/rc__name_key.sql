CREATE OR REPLACE FUNCTION public.rc__name_key(p text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select lower(regexp_replace(trim(coalesce(p, '')), '\s+', '', 'g')) $function$

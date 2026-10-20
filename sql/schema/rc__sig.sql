CREATE OR REPLACE FUNCTION public.rc__sig(p text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'extensions'
AS $function$
  select encode(extensions.digest('rc-collec#7b2e-foc|' || p, 'sha256'), 'hex') $function$

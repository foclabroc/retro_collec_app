CREATE OR REPLACE FUNCTION public.rc__chat_key(p text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select regexp_replace(
           regexp_replace(
             translate(lower(p), 'àâäáãéèêëíìîïóòôöõúùûüçñ013457@$!|', 'aaaaaeeeeiiiiooooouuuucnoieastasii'),
             '[^a-z]', '', 'g'),
           '(.)\1+', '\1', 'g') $function$

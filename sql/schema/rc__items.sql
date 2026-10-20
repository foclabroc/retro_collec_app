CREATE OR REPLACE FUNCTION public.rc__items(p text)
 RETURNS TABLE(card text, finish integer, n integer)
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select split_part(x, ':', 1), coalesce(nullif(split_part(x, ':', 2), ''), '0')::int, count(*)::int
    from unnest(string_to_array(coalesce(p, ''), ',')) x
   where x <> ''
   group by 1, 2 $function$

CREATE OR REPLACE FUNCTION public.rc__special_cost(p_kind text)
 RETURNS integer
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select case p_kind when 'star' then 15 when 'sconsole' then 25 when 'gold' then 40 end $function$

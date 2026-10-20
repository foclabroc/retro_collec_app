CREATE OR REPLACE FUNCTION public.rc__bs_len(p_k text)
 RETURNS integer
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select case p_k when 'neo' then 5 when 'ps' then 4 when 'md' then 3 when 'nes' then 3 when 'gb' then 2 end $function$

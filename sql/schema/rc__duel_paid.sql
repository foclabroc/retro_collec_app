CREATE OR REPLACE FUNCTION public.rc__duel_paid(p_a text, p_b text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select public.rc__duel_why(p_a, p_b) is null $function$

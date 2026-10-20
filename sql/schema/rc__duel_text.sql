CREATE OR REPLACE FUNCTION public.rc__duel_text(p text)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  select nullif(left(public.rc__chat_clean(left(coalesce(p, ''), 120)), 60), '') $function$

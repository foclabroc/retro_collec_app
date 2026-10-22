create or replace function public.rc__name_key(p text)
 returns text
 language sql
 immutable
as $function$
  select lower(regexp_replace(coalesce(p, ''), '[^[:alnum:]]', '', 'g')) $function$;

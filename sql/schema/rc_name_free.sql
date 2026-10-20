CREATE OR REPLACE FUNCTION public.rc_name_free(p_name text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select public.rc__name_key(left(trim(coalesce(p_name, '')), 16)) <> ''
     and not exists (select 1 from public.rc_players
                      where name_key = public.rc__name_key(left(trim(coalesce(p_name, '')), 16))) $function$

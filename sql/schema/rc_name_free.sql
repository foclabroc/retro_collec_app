create or replace function public.rc_name_free(p_name text)
 returns boolean
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select public.rc__name_key(left(trim(coalesce(p_name, '')), 24)) <> ''
     and not exists (select 1 from public.rc_players
                      where name_key = public.rc__name_key(left(trim(coalesce(p_name, '')), 24))) $function$;

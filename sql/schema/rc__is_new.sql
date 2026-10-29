create or replace function public.rc__is_new(p_device text, p_card text, p_finish int)
 returns boolean
 language sql
 stable
 set search_path to 'public'
as $function$
  select not exists (select 1 from public.rc_owned
                      where device = p_device and card = p_card and qty > 0
                        and (finish = 3) = (coalesce(p_finish, 0) = 3))
$function$;

create or replace function public.rc__wheel_gold(p_device text)
 returns boolean
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select coalesce((select p.streak > 0 and p.streak % 7 = 0 and p.last_login = public.rc__today()
                          and p.wheel_day is distinct from public.rc__today()
                     from public.rc_players p where p.device = p_device), false) $function$;

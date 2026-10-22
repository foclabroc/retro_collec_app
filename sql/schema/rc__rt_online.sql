create or replace function public.rc__rt_online()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
begin
  perform public.rc__rt_safe('rc_all', 'online', jsonb_build_object('pid', new.pid));
  return null;
end $function$

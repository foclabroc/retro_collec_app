create or replace function public.rc__rt_stock()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
begin
  perform public.rc__rt_safe(public.rc__rt_topic(new.device), 'me', '{"k":"gift"}');
  return null;
exception when others then
  return null;
end $function$;

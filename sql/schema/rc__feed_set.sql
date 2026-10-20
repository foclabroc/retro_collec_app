CREATE OR REPLACE FUNCTION public.rc__feed_set()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if new.step = 100 then
    perform public.rc__feed_add(new.device, 'set', null, null, new.sys, null);
  elsif new.step = 50 then
    perform public.rc__feed_put(new.device, 'half', null, null, null, new.sys, null, null, true);
  end if;
  return new;
end $function$

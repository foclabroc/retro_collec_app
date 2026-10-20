CREATE OR REPLACE FUNCTION public.rc__feed_join()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  perform public.rc__feed_put(new.device, 'join', null, null, null, null, null, null);
  return new;
end $function$

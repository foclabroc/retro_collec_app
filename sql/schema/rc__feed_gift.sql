CREATE OR REPLACE FUNCTION public.rc__feed_gift()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if new.giver is null or not exists (select 1 from public.rc_players where device = new.giver) then return new; end if;
  perform public.rc__feed_put(new.giver, 'gift', new.receiver, null, null, null, null, null, true);
  return new;
end $function$

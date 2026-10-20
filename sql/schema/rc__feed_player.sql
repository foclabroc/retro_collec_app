CREATE OR REPLACE FUNCTION public.rc__feed_player()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s int;
begin
  if new.streak is distinct from old.streak and new.streak in (7, 30, 100, 365) and new.streak > coalesce(old.streak, 0) then
    perform public.rc__feed_put(new.device, 'streak', null, null, null, null, new.streak, null, true);
  end if;
  if new.packs > coalesce(old.packs, 0) then
    select max(x) into s from unnest(array[100, 250, 500, 1000, 2000, 5000, 10000]) x
     where x > coalesce(old.packs, 0) and x <= new.packs;
    if s is not null then perform public.rc__feed_put(new.device, 'packs', null, null, null, null, s, null, true); end if;
  end if;
  return new;
end $function$

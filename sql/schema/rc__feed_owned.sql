CREATE OR REPLACE FUNCTION public.rc__feed_owned()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r int; sg text;
begin
  if tg_op = 'UPDATE' and new.qty <= old.qty then return new; end if;
  select rarity, saga into r, sg from public.rc_cards where id = new.card;
  if sg is not null then
    perform public.rc__feed_add(new.device, 'saga', new.card, 0, null, null);
  elsif new.finish = 3 then
    perform public.rc__feed_add(new.device, 'fullart', new.card, 3, null, null);
  elsif new.finish = 2 then
    perform public.rc__feed_add(new.device, 'gold', new.card, 2, null, null);
  elsif r = 4 then
    perform public.rc__feed_add(new.device, 'legend', new.card, new.finish, null, null);
  end if;
  return new;
end $function$

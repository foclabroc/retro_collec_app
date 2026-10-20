CREATE OR REPLACE FUNCTION public.rc__feed_sale()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if new.buyer is null or old.buyer is not null then return new; end if;
  if (select rarity from public.rc_cards where id = new.card) < 3 then return new; end if;
  perform public.rc__feed_put(new.buyer, 'sale', new.seller, new.card, new.finish, null, new.price, null);
  return new;
end $function$

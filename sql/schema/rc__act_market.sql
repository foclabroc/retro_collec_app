create or replace function public.rc__act_market()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
begin
  begin
    if tg_op = 'INSERT' then
      perform public.rc__act(new.seller, 'sell', 2, 'met en vente à ' || new.price || ' pièces', new.card, new.finish);
    elsif tg_op = 'UPDATE' then
      if new.buyer is not null and old.buyer is null then
        perform public.rc__act(new.buyer,  'buy',  2, 'achète à ' || new.price || ' pièces à', new.card, new.finish, new.seller);
        perform public.rc__act(new.seller, 'sold', 2, 'vend à ' || new.price || ' pièces à', new.card, new.finish, new.buyer);
      end if;
    elsif old.buyer is null then
      perform public.rc__act(old.seller, 'unsell', 2, 'retire de la Bourse', old.card, old.finish);
      return old;
    end if;
  exception when others then null;
  end;
  return coalesce(new, old);
end $function$;

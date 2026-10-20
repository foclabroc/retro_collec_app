CREATE OR REPLACE FUNCTION public.rc__feed_trade()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  items text[];
  best record;
begin
  if new.status <> 'accepted' or old.status = 'accepted' then return new; end if;
  items := array_remove(string_to_array(coalesce(new.give, '') || ',' || coalesce(new.want, ''), ','), '');
  select c.id, (regexp_match(x, ':([0-9]+)$'))[1]::int as f into best
    from unnest(items) x join public.rc_cards c on c.id = regexp_replace(x, ':[0-9]+$', '')
   order by c.rarity desc, 2 desc nulls last limit 1;
  perform public.rc__feed_put(new.sender, 'trade', new.receiver, best.id, best.f, null, coalesce(array_length(items, 1), 0), null);
  return new;
end $function$

CREATE OR REPLACE FUNCTION public.rc__items_value(p text)
 RETURNS integer
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(sum(public.rc__recycle_value(c.rarity, i.finish) * i.n), 0)::int
    from public.rc__items(p) i join public.rc_cards c on c.id = i.card $function$

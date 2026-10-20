CREATE OR REPLACE FUNCTION public.rc__rescore(p_dev text)
 RETURNS void
 LANGUAGE sql
AS $function$
  update public.rc_players p set
    cards = (select count(distinct o.card) from public.rc_owned o where o.device = p_dev),
    score = coalesce((select sum(public.rc__pts(c.rarity) * (case o.finish when 0 then 1 when 1 then 1 when 2 then 3 else 6 end))
                        from public.rc_owned o join public.rc_cards c on c.id = o.card
                       where o.device = p_dev), 0),
    updated_at = now()
  where p.device = p_dev $function$

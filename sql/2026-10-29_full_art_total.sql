-- 29/10/2026 (suite) : une full art compte comme une carte de plus dans le total
-- (rc_players.cards = cartes normales / brillantes / dorées + full art, chacune une fois).
-- Les paliers de console restent sans full art. Relançable.

CREATE OR REPLACE FUNCTION public.rc__rescore(p_dev text)
 RETURNS void
 LANGUAGE sql
AS $function$
  update public.rc_players p set
    cards = (select count(distinct o.card) filter (where o.finish <> 3) + count(distinct o.card) filter (where o.finish = 3)
               from public.rc_owned o where o.device = p_dev and o.qty > 0),  -- une full art = une carte de plus (onglet à part)
    score = coalesce((select sum(public.rc__pts(c.rarity) * (case o.finish when 0 then 1 when 1 then 1 when 2 then 3 else 6 end))
                        from public.rc_owned o join public.rc_cards c on c.id = o.card
                       where o.device = p_dev), 0),
    updated_at = now()
  where p.device = p_dev $function$;

do $$ declare d text; begin
  for d in select device from public.rc_players loop perform public.rc__rescore(d); end loop;
end $$;

notify pgrst, 'reload schema';

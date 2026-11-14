-- 14/11/2026 : full art = carte a part, aussi dans « Demander en echange » (Bourse).
-- Avant : une normale + une full art comptaient comme 2 exemplaires (donc « en double »).
-- Maintenant : seuls les exemplaires normale / brillante / doree comptent (full art a part).
-- Relancable.
CREATE OR REPLACE FUNCTION public.rc_card_owners(p_device text, p_card text)
 RETURNS TABLE(pid text, name text, avatar integer, qty integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select p.pid, p.name, p.avatar, sum(o.qty)::int
    from public.rc_owned o
    join public.rc_players p on p.device = o.device
   where o.card = p_card and o.device <> p_device and o.finish < 3
   group by p.pid, p.name, p.avatar, p.updated_at
  having sum(o.qty) >= 2
   order by sum(o.qty) desc, p.updated_at desc
   limit 20 $function$;

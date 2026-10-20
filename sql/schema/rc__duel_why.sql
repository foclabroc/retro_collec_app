CREATE OR REPLACE FUNCTION public.rc__duel_why(p_a text, p_b text)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select case
    when exists (select 1 from public.rc_players where device in (p_a, p_b) and created_at > now() - interval '1 day') then 'new'
    when (select count(*) from (
            select 1 from public.rc_c4 g where g.paid and ((g.p1 = p_a and g.p2 = p_b) or (g.p1 = p_b and g.p2 = p_a))
               and (g.move_at at time zone 'Europe/Paris')::date = (now() at time zone 'Europe/Paris')::date
            union all
            select 1 from public.rc_bs g where g.paid and ((g.p1 = p_a and g.p2 = p_b) or (g.p1 = p_b and g.p2 = p_a))
               and (g.move_at at time zone 'Europe/Paris')::date = (now() at time zone 'Europe/Paris')::date) x) >= 4 then 'limit'
  end $function$

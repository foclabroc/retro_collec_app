create or replace function public.rc_rank(p_device text)
 RETURNS TABLE(rank integer, total integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select (select count(*)::int + 1 from public.rc_players o
           where o.packs > 0 and greatest(o.seen_at, o.last_login::timestamptz) > now() - interval '7 days' and o.score > (select p.score from public.rc_players p where p.device = p_device)),
         (select count(*)::int from public.rc_players q where q.packs > 0 and greatest(q.seen_at, q.last_login::timestamptz) > now() - interval '7 days') $function$
;

$function$;

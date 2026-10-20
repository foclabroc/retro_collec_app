CREATE OR REPLACE FUNCTION public.rc_gifts_list(p_device text)
 RETURNS TABLE(id bigint, name text, pid text, avatar integer, at timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select g.id, coalesce(p.name, g.giver_name), p.pid, coalesce(p.avatar, 0), g.created_at
    from public.rc_gifts g left join public.rc_players p on p.device = g.giver
   where g.receiver = p_device and g.opened_at is null
   order by g.id $function$

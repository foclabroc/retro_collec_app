CREATE OR REPLACE FUNCTION public.rc_trades(p_device text)
 RETURNS TABLE(id bigint, incoming boolean, other_name text, other_pid text, give text, want text, status text, created_at timestamp with time zone, done_at timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  (select t.id, t.receiver = p_device, o.name, o.pid, t.give, t.want, t.status, t.created_at, t.done_at
     from public.rc_trades t
     join public.rc_players o on o.device = case when t.receiver = p_device then t.sender else t.receiver end
    where (t.sender = p_device or t.receiver = p_device) and t.status = 'pending'
    order by t.created_at desc)
  union all
  (select t.id, t.receiver = p_device, o.name, o.pid, t.give, t.want, t.status, t.created_at, t.done_at
     from public.rc_trades t
     join public.rc_players o on o.device = case when t.receiver = p_device then t.sender else t.receiver end
    where (t.sender = p_device or t.receiver = p_device) and t.status <> 'pending'
    order by t.done_at desc nulls last
    limit 20) $function$

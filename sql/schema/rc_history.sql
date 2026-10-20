CREATE OR REPLACE FUNCTION public.rc_history(p_device text)
 RETURNS TABLE(kind text, card text, finish smallint, price integer, other_name text, other_pid text, give text, want text, status text, at timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select * from (
    select 'sold'::text, m.card, m.finish, m.price, b.name, b.pid, null::text, null::text, null::text, m.sold_at
      from public.rc_market m left join public.rc_players b on b.device = m.buyer
     where m.seller = p_device and m.buyer is not null
    union all
    select 'bought', m.card, m.finish, m.price, s.name, s.pid, null, null, null, m.sold_at
      from public.rc_market m left join public.rc_players s on s.device = m.seller
     where m.buyer = p_device
    union all
    select case when t.receiver = p_device then 'trade_in' else 'trade_out' end, null, null, null, o.name, o.pid,
           t.give, t.want, t.status, coalesce(t.done_at, t.created_at)
      from public.rc_trades t
      join public.rc_players o on o.device = case when t.receiver = p_device then t.sender else t.receiver end
     where (t.sender = p_device or t.receiver = p_device) and t.status <> 'pending'
  ) h
  order by 10 desc
  limit 50 $function$

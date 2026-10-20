CREATE OR REPLACE FUNCTION public.rc_history_page(p_device text, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with h as (
    select 'sold'::text as kind, m.card, m.finish, m.price, b.name as other_name, b.pid as other_pid,
           null::text as give, null::text as want, null::text as status, m.sold_at as at
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
     where (t.sender = p_device or t.receiver = p_device) and t.status <> 'pending')
  select jsonb_build_object(
    'rows', coalesce((select jsonb_agg(to_jsonb(x) order by x.at desc) from
                        (select * from h order by at desc offset greatest(coalesce(p_offset, 0), 0) limit 50) x), '[]'::jsonb),
    'more', (select count(*) from h) > greatest(coalesce(p_offset, 0), 0) + 50,
    'earned', coalesce((select sum(price) from h where kind = 'sold'), 0),
    'spent', coalesce((select sum(price) from h where kind = 'bought'), 0),
    'trades', (select count(*) from h where kind like 'trade%' and status = 'accepted')) $function$

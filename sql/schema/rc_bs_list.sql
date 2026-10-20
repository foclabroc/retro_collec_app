CREATE OR REPLACE FUNCTION public.rc_bs_list(p_device text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r record;
begin
  update public.rc_players set seen_at = now() where device = p_device;
  for r in select id from public.rc_bs where (p1 = p_device or p2 = p_device) and status in ('invite', 'setup', 'playing') loop
    perform public.rc__bs_settle(r.id);
  end loop;
  return coalesce((
    select jsonb_agg(public.rc__bs_json(g, p_device) order by
             case g.status when 'setup' then 0 when 'playing' then 0 when 'invite' then 1 else 2 end, g.move_at desc)
      from (select * from public.rc_bs x
             where (x.p1 = p_device or x.p2 = p_device)
               and (x.status <> 'done' or x.move_at > now() - interval '3 days' or x.created_at > now() - interval '3 days')
             order by x.id desc limit 40) g), '[]'::jsonb);
end $function$

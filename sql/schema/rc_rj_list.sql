create or replace function public.rc_rj_list(p_device text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare r record;
begin
  update public.rc_players set seen_at = now() where device = p_device;
  for r in select id from public.rc_rj where (p1 = p_device or p2 = p_device) and status in ('invite', 'playing') loop
    perform public.rc__rj_settle(r.id);
  end loop;
  return coalesce((
    select jsonb_agg(public.rc__rj_json(g, p_device) order by
             case g.status when 'playing' then 0 when 'invite' then 1 else 2 end, g.move_at desc)
      from (select * from public.rc_rj x
             where (x.p1 = p_device or x.p2 = p_device)
               and (x.status <> 'done' or x.move_at > now() - interval '3 days')
             order by x.id desc limit 40) g), '[]'::jsonb);
end $function$;

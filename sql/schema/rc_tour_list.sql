create or replace function public.rc_tour_list(p_device text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
begin
  perform public.rc__tour_tick();
  return (select coalesce(jsonb_agg(public.rc__tour_json(t.id, p_device, false)
                   order by case t.status when 'running' then 0 when 'open' then 1 else 2 end,
                            case when t.status in ('open', 'running') then t.start_at end,
                            t.ended_at desc nulls last), '[]'::jsonb)
            from (select * from public.rc_tour
                   where status in ('open', 'running') or ended_at > now() - interval '7 days'
                   order by id desc limit 20) t);
end $function$;

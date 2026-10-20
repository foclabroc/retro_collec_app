create or replace function public.rc__ev_bump(p_dev text, p_goal text, p_n integer, p_arg text default null)
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
begin
  if p_dev is null or coalesce(p_n, 0) <= 0 then return; end if;
  insert into public.rc_events_prog (device, event_id, n)
  select p_dev, e.id, p_n from public.rc_events e
   where e.kind = 'goal' and e.goal = p_goal and public.rc__ev_live(e)
     and (p_goal <> 'console' or e.arg = p_arg)
  on conflict (device, event_id) do update set n = public.rc_events_prog.n + excluded.n;
end $function$;

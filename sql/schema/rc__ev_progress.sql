create or replace function public.rc__ev_progress(p_dev text, e rc_events)
 returns integer
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select case e.goal
    when 'c4_wins' then (select count(*)::int from public.rc_c4 g
                          where g.status = 'done' and g.move_at >= e.starts_at and (e.ends_at is null or g.move_at < e.ends_at)
                            and ((g.p1 = p_dev and g.winner = 1) or (g.p2 = p_dev and g.winner = 2)))
    when 'bs_wins' then (select count(*)::int from public.rc_bs g
                          where g.status = 'done' and g.move_at >= e.starts_at and (e.ends_at is null or g.move_at < e.ends_at)
                            and ((g.p1 = p_dev and g.winner = 1) or (g.p2 = p_dev and g.winner = 2)))
    when 'gamedle' then (select count(*)::int from public.rc_gamedle d
                          where d.device = p_dev and d.won
                            and d.day >= (e.starts_at at time zone 'Europe/Paris')::date
                            and (e.ends_at is null or d.day <= (e.ends_at at time zone 'Europe/Paris')::date))
    -- compteurs tenus par le serveur (packs, sales, trades, recycle, epics, gifts_sent, quiz, console)
    else coalesce((select n from public.rc_events_prog where device = p_dev and event_id = e.id), 0) end $function$;

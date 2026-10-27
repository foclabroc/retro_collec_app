create or replace function public.rc__duel_busy(p_device text)
 returns boolean
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select exists (select 1 from public.rc_c4 g where g.mode = 'live' and g.status = 'playing'
                  and p_device in (g.p1, g.p2) and now() <= g.move_at + interval '60 seconds')
      or exists (select 1 from public.rc_bs g where g.mode = 'live' and g.status in ('setup', 'playing')
                  and p_device in (g.p1, g.p2) and now() <= g.move_at + interval '2 minutes')
      or exists (select 1 from public.rc_rj g where g.status = 'playing'
                  and p_device in (g.p1, g.p2) and now() <= g.end_at + interval '10 seconds') $function$;

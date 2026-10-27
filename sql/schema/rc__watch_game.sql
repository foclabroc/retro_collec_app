create or replace function public.rc__watch_game(p_game text, p_id bigint)
 returns table(p1 text, p2 text)
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select g.p1, g.p2 from public.rc_c4 g
   where p_game = 'c4' and g.id = p_id and g.mode = 'live' and g.status = 'playing'
  union all
  select g.p1, g.p2 from public.rc_bs g
   where p_game = 'bs' and g.id = p_id and g.mode = 'live' and g.status in ('setup', 'playing')
  union all
  select g.p1, g.p2 from public.rc_rj g
   where p_game = 'rj' and g.id = p_id and g.status = 'playing' $function$;

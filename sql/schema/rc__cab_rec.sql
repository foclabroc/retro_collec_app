create or replace function public.rc__cab_rec(p_owner text, p_game text)
 returns table(device text, score int)
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select b.device, b.score from public.rc_cab_best b
   where b.owner = p_owner and b.game = p_game and b.week = public.rc__cab_week()
   order by b.score desc, b.at asc limit 1 $function$;

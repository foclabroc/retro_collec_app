create or replace function public.rc__cab_game(p_game text, p_pid text)
 returns text
 language sql
 immutable
as $function$
  select coalesce(p_game, (array['snake', 'bricks', 'dodge'])[1 + abs(hashtext(coalesce(p_pid, ''))) % 3]) $function$;

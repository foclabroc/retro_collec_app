create or replace function public.rc_watchers(p_game text, p_id bigint)
 returns jsonb
 language sql
 stable security definer
 set search_path to 'public'
as $function$ select public.rc__watch_list(p_game, p_id) $function$;

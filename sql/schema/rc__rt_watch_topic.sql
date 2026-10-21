create or replace function public.rc__rt_watch_topic(p_game text, p_id bigint)
 returns text
 language sql
 immutable
 set search_path to 'public', 'extensions'
as $function$
  select 'rc_' || left(encode(extensions.digest('watch|' || p_game || '|' || p_id, 'sha256'), 'hex'), 24) $function$;

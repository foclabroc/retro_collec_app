create or replace function public.rc__rt_topic(p_device text)
 returns text
 language sql
 immutable
 set search_path to 'public', 'extensions'
as $function$
  select 'rc_' || left(encode(extensions.digest('rt|' || p_device, 'sha256'), 'hex'), 24) $function$;

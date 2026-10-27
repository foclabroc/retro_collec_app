create or replace function public.rc__ip()
 returns text
 language sql
 stable
 set search_path to 'public', 'extensions'
as $function$
  select case when k is null then null else encode(extensions.digest('ip|' || k, 'sha256'), 'hex') end
    from (select public.rc__ip_key(trim(split_part(coalesce(nullif(current_setting('request.headers', true), '')::json ->> 'x-forwarded-for', ''), ',', 1))) as k) x $function$;

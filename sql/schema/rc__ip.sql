create or replace function public.rc__ip()
 returns text
 language sql
 stable
 set search_path to 'public', 'extensions'
as $function$
  select case when ip = '' then null else encode(extensions.digest('ip|' || ip, 'sha256'), 'hex') end
    from (select trim(split_part(coalesce(nullif(current_setting('request.headers', true), '')::json ->> 'x-forwarded-for', ''), ',', 1)) as ip) x $function$

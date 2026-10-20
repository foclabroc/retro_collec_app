create or replace function public.rc_app_config()
 returns jsonb
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select jsonb_build_object('min_version', coalesce((select value #>> '{}' from public.rc_config where key = 'min_version'), '1.0.0'),
                            'live', public.rc__live(),
                            'banner', (select value from public.rc_config where key = 'banner'
                                        and coalesce(value->>'text', '') <> ''
                                        and (value->>'until' is null or (value->>'until')::timestamptz > now())),
                            'maintenance', (select value from public.rc_config where key = 'maintenance' and (value->>'on')::boolean)) $function$;

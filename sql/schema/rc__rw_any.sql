create or replace function public.rc__rw_any(r jsonb)
 returns boolean
 language sql
 immutable
as $function$
  select coalesce((r->>'coins')::int, 0) > 0 or coalesce((r->>'pixels')::int, 0) > 0 or coalesce((r->>'lots')::int, 0) > 0
      or exists (select 1 from jsonb_each_text(coalesce(r->'packs', '{}'::jsonb)) x where x.value::int > 0)
      or exists (select 1 from jsonb_each_text(coalesce(r->'cards', '{}'::jsonb)) x where x.value::int > 0) $function$;

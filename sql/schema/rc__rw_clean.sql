create or replace function public.rc__rw_clean(r jsonb)
 returns jsonb
 language plpgsql
 immutable
as $function$
declare out jsonb := '{}'::jsonb; m jsonb := '{}'::jsonb; k text; v text; n int;
begin
  if r is null or jsonb_typeof(r) <> 'object' then return '{}'::jsonb; end if;
  n := least(greatest(coalesce((r->>'coins')::int, 0), 0), 100000); if n > 0 then out := out || jsonb_build_object('coins', n); end if;
  n := least(greatest(coalesce((r->>'pixels')::int, 0), 0), 1000);  if n > 0 then out := out || jsonb_build_object('pixels', n); end if;
  n := least(greatest(coalesce((r->>'lots')::int, 0), 0), 5);       if n > 0 then out := out || jsonb_build_object('lots', n); end if;
  for k, v in select key, value from jsonb_each_text(coalesce(r->'packs', '{}'::jsonb)) loop
    n := least(greatest(coalesce(v::int, 0), 0), 10);
    if k in ('mixte', 'premium', 'mystery', 'star', 'gold') and n > 0 then m := m || jsonb_build_object(k, n); end if;
  end loop;
  if m <> '{}'::jsonb then out := out || jsonb_build_object('packs', m); end if;
  m := '{}'::jsonb;
  for k, v in select key, value from jsonb_each_text(coalesce(r->'cards', '{}'::jsonb)) loop
    n := least(greatest(coalesce(v::int, 0), 0), 10);
    if k in ('0', '1', '2', '3', '4') and n > 0 then m := m || jsonb_build_object(k, n); end if;
  end loop;
  if m <> '{}'::jsonb then out := out || jsonb_build_object('cards', m); end if;
  return out;
end $function$;

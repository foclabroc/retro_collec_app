create or replace function public.rc__rw_add(a jsonb, b jsonb)
 returns jsonb
 language plpgsql
 immutable
as $function$
declare r jsonb; k text; v text; m jsonb;
begin
  a := coalesce(a, '{}'::jsonb); b := coalesce(b, '{}'::jsonb);
  r := jsonb_build_object(
    'coins', coalesce((a->>'coins')::int, 0) + coalesce((b->>'coins')::int, 0),
    'pixels', coalesce((a->>'pixels')::int, 0) + coalesce((b->>'pixels')::int, 0),
    'lots', coalesce((a->>'lots')::int, 0) + coalesce((b->>'lots')::int, 0));
  -- paquets
  m := coalesce(a->'packs', '{}'::jsonb);
  for k, v in select key, value from jsonb_each_text(coalesce(b->'packs', '{}'::jsonb)) loop
    m := m || jsonb_build_object(k, coalesce((m->>k)::int, 0) + coalesce(v::int, 0));
  end loop;
  r := r || jsonb_build_object('packs', m);
  -- cartes
  m := coalesce(a->'cards', '{}'::jsonb);
  for k, v in select key, value from jsonb_each_text(coalesce(b->'cards', '{}'::jsonb)) loop
    m := m || jsonb_build_object(k, coalesce((m->>k)::int, 0) + coalesce(v::int, 0));
  end loop;
  return r || jsonb_build_object('cards', m);
end $function$;

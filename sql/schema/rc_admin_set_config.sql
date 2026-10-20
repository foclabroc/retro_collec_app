create or replace function public.rc_admin_set_config(p_device text, p_sig text, p_key text, p_value text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare j jsonb;
begin
  perform public.rc__admin(p_device, p_sig, 'config|' || coalesce(p_key, '') || '|' || coalesce(p_value, ''));
  if p_key = 'min_version' then
    if p_value !~ '^\d+\.\d+\.\d+$' then raise exception 'version invalide (ex. 1.0.12)'; end if;
    insert into public.rc_config (key, value) values ('min_version', to_jsonb(p_value))
    on conflict (key) do update set value = excluded.value;
  elsif p_key = 'banner' then
    -- {"text": "...", "until": "2026-10-20T20:00:00Z"} ; texte vide = pas de bandeau
    j := coalesce(nullif(p_value, ''), '{}')::jsonb;
    insert into public.rc_config (key, value)
    values ('banner', jsonb_build_object('text', left(trim(coalesce(j->>'text', '')), 200), 'until', j->>'until'))
    on conflict (key) do update set value = excluded.value;
  elsif p_key = 'maintenance' then
    -- {"on": true, "msg": "..."}
    j := coalesce(nullif(p_value, ''), '{}')::jsonb;
    insert into public.rc_config (key, value)
    values ('maintenance', jsonb_build_object('on', coalesce((j->>'on')::boolean, false), 'msg', left(coalesce(j->>'msg', ''), 300)))
    on conflict (key) do update set value = excluded.value;
  else
    raise exception 'réglage inconnu';
  end if;
  return public.rc_app_config();
end $function$;

CREATE OR REPLACE FUNCTION public.rc_ref_set(p_device text, p_code text, p_sig text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare v public.rc_players; s public.rc_players; k text; n int;
begin
  perform public.rc__check(p_sig, p_device || '|refset|' || coalesce(p_code, ''));
  select * into v from public.rc_players where device = p_device for update;
  if v.device is null then raise exception 'joueur inconnu'; end if;
  k := lower(regexp_replace(upper(coalesce(p_code, '')), '^PT-?|[^0-9A-F]', '', 'g'));
  if v.referrer is not null then return jsonb_build_object('res', 'already') || public.rc__ref_json(p_device); end if;
  if v.created_at < now() - interval '7 days' then return jsonb_build_object('res', 'late') || public.rc__ref_json(p_device); end if;
  if length(k) <> 6 then return jsonb_build_object('res', 'unknown') || public.rc__ref_json(p_device); end if;
  select count(*) into n from public.rc_players where left(pid, 6) = k;
  if n <> 1 then return jsonb_build_object('res', 'unknown') || public.rc__ref_json(p_device); end if;
  select * into s from public.rc_players where left(pid, 6) = k;
  if s.device = p_device then return jsonb_build_object('res', 'self') || public.rc__ref_json(p_device); end if;
  if s.referrer = p_device then return jsonb_build_object('res', 'self') || public.rc__ref_json(p_device); end if;  -- pas de parrainage croisé
  if (select count(*) from public.rc_players where referrer = s.device) >= 10 then
    return jsonb_build_object('res', 'full') || public.rc__ref_json(p_device);
  end if;
  update public.rc_players set referrer = s.device where device = p_device;
  perform public.rc__ref_check(p_device);
  return jsonb_build_object('res', 'ok') || public.rc__ref_json(p_device);
end $function$

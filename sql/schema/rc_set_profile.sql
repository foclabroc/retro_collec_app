CREATE OR REPLACE FUNCTION public.rc_set_profile(p_device text, p_name text, p_avatar integer, p_showcase text, p_sig text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  v_name text := left(trim(coalesce(p_name, '')), 16);
  v_key  text := public.rc__name_key(left(trim(coalesce(p_name, '')), 16));
begin
  perform public.rc__check(p_sig, p_device || '|profile|' || coalesce(p_name, '') || '|' || p_avatar || '|' || coalesce(p_showcase, ''));
  if v_key = '' then raise exception 'pseudo vide'; end if;
  if exists (select 1 from public.rc_players where name_key = v_key and device <> p_device) then return 'taken'; end if;
  if (select count(*) from public.rc__items(p_showcase)) > 6 or not public.rc__has(p_device, p_showcase) then
    return 'showcase';
  end if;
  update public.rc_players set name = v_name, name_key = v_key, avatar = least(greatest(coalesce(p_avatar, 0), 0), 63),
         showcase = coalesce(p_showcase, ''), updated_at = now()
   where device = p_device;
  return 'ok';
end $function$

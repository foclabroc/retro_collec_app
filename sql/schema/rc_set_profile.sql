create or replace function public.rc_set_profile(p_device text, p_name text, p_avatar integer, p_showcase text, p_sig text)
 returns text
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare
  v_name text := left(trim(coalesce(p_name, '')), 24);
  v_key  text := public.rc__name_key(left(trim(coalesce(p_name, '')), 24));
  v_show text;
begin
  perform public.rc__check(p_sig, p_device || '|profile|' || coalesce(p_name, '') || '|' || p_avatar || '|' || coalesce(p_showcase, ''));
  if v_key = '' then raise exception 'pseudo vide'; end if;
  if exists (select 1 from public.rc_players where name_key = v_key and device <> p_device) then return 'taken'; end if;
  if (select count(*) from public.rc__items(p_showcase)) > 6 then return 'showcase'; end if;
  if public.rc__has(p_device, p_showcase) then
    v_show := coalesce(p_showcase, '');
  else
    -- garde, dans l'ordre, les exemplaires encore possÃ©dÃ©s
    select coalesce(string_agg(x.e, ',' order by x.pos), '') into v_show
      from (select e, pos, row_number() over (partition by e order by pos) as rn
              from unnest(string_to_array(coalesce(p_showcase, ''), ',')) with ordinality as u(e, pos)
             where e <> '') x
      left join public.rc_owned o on o.device = p_device and o.card = split_part(x.e, ':', 1)
           and o.finish = coalesce(nullif(split_part(x.e, ':', 2), ''), '0')::int
     where coalesce(o.qty, 0) >= x.rn;
  end if;
  update public.rc_players set name = v_name, name_key = v_key, avatar = least(greatest(coalesce(p_avatar, 0), 0), 63),
         showcase = v_show, updated_at = now()
   where device = p_device;
  return 'ok';
end $function$;

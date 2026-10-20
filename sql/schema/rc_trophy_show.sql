create or replace function public.rc_trophy_show(p_device text, p_list text, p_sig text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare a text[]; i int; s text := '';
begin
  perform public.rc__check(p_sig, p_device || '|tshow|' || coalesce(p_list, ''));
  if not exists (select 1 from public.rc_players where device = p_device) then raise exception 'joueur inconnu'; end if;
  a := string_to_array(coalesce(p_list, ''), ',');
  for i in 1..3 loop
    -- seulement des trophées débloqués (au moins bronze), sans doublon
    if i > 1 then s := s || ','; end if;
    if i <= coalesce(array_length(a, 1), 0) and a[i] <> ''
       and exists (select 1 from public.rc_trophy_got g where g.device = p_device and g.kind = a[i] and g.tier > 0)
       and not (a[i] = any(a[1:i - 1])) then
      s := s || a[i];
    end if;
  end loop;
  update public.rc_players set trophies = case when replace(s, ',', '') = '' then '' else s end where device = p_device;
  return public.rc__tro_json(p_device);
end $function$;

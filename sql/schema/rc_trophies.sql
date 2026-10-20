create or replace function public.rc_trophies(p_device text, p_sig text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
begin
  perform public.rc__check(p_sig, p_device || '|trophies');
  if not exists (select 1 from public.rc_players where device = p_device) then raise exception 'joueur inconnu'; end if;
  -- cadeau de passage en 1.0.13 (seule cette version appelle les trophées) : 1 paquet premium + 500 pièces, une fois
  insert into public.rc_upgrade_got (device, ver) values (p_device, '1.0.13') on conflict do nothing;
  if found then
    insert into public.rc_gifts (receiver, giver, giver_name, kind) values (p_device, null, 'Mise à jour 1.0.13', 'premium');
    update public.rc_players set coins = coins + 500 where device = p_device;
  end if;
  return public.rc__tro_json(p_device);
end $function$;

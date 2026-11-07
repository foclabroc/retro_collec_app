CREATE OR REPLACE FUNCTION public.rc_sunday_claim(p_device text, p_sig text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare v public.rc_players;
begin
  perform public.rc__check(p_sig, p_device || '|sunday');
  select * into v from public.rc_players where device = p_device for update;
  if v.device is null then raise exception 'joueur inconnu'; end if;
  if not public.rc__sunday() then raise exception 'seulement le dimanche'; end if;
  if v.sunday_got is not distinct from public.rc__today() then raise exception 'deja recupere aujourd''hui'; end if;
  update public.rc_players set sunday_got = public.rc__today() where device = p_device;
  perform set_config('rc.gift_from', 'Cadeau du dimanche', true);
  perform public.rc__grant(p_device, '{"packs": {"pokemon": 1, "cartoon": 1, "dragonball": 1}}'::jsonb);
  perform set_config('rc.gift_from', '', true);
  perform public.rc__tbump(p_device, 'sunday', 1);
  return jsonb_build_object('ok', true,
    'gifts', (select count(*)::int from public.rc_gifts g where g.receiver = p_device and g.opened_at is null));
end $function$


create or replace function public.rc_upgrade_gift(p_device text, p_ver text, p_sig text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare
  v_rw jsonb; v_out timestamptz;
begin
  perform public.rc__check(p_sig, p_device || '|upgrade|' || p_ver);
  if not exists (select 1 from public.rc_players where device = p_device) then raise exception 'joueur inconnu'; end if;
  -- cadeau par version (même JSON que les récompenses → rc__grant) + date de sortie de la version :
  -- seuls les comptes créés avant la sortie le reçoivent (un nouveau compte ne peut pas réclamer les anciens)
  select x.rw, x.out_at into v_rw, v_out from (values
    ('1.0.16', '{"coins":500}'::jsonb, timestamptz '2026-10-21 09:30+00'),
    ('1.0.18', '{"coins":600,"pixels":8,"packs":{"premium":1}}'::jsonb, timestamptz '2026-10-22 06:45+00')
  ) x(ver, rw, out_at) where x.ver = p_ver;
  if v_rw is null then return jsonb_build_object('coins', 0); end if;
  if exists (select 1 from public.rc_players where device = p_device and created_at >= v_out) then
    return jsonb_build_object('coins', 0);
  end if;
  insert into public.rc_upgrade_got (device, ver) values (p_device, p_ver) on conflict do nothing;
  if not found then return jsonb_build_object('coins', 0); end if;
  perform public.rc__grant(p_device, v_rw);
  return jsonb_build_object('coins', coalesce((v_rw->>'coins')::int, 0), 'reward', v_rw);
end $function$

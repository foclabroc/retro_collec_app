-- 27/10/2026 : la 1.0.25 (comme la 1.0.24) n'a pas de cadeau propre ; elle donne le cadeau 1.0.23 (600 pièces + 1 booster premium)
-- à ceux qui ne l'ont pas encore eu, une seule fois en tout (rc_upgrade_got, version '1.0.23'),
-- seulement aux comptes créés avant la sortie de la 1.0.23. Remplace sql/2026-10-27_cadeau_1024.sql. Relançable.

create or replace function public.rc_upgrade_gift(p_device text, p_ver text, p_sig text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare
  v_rw jsonb; v_out timestamptz; v_ver text;
begin
  perform public.rc__check(p_sig, p_device || '|upgrade|' || p_ver);
  if not exists (select 1 from public.rc_players where device = p_device) then raise exception 'joueur inconnu'; end if;
  -- version de l'appli (vue par l'admin) : p_ver = « 1.0.21|android » (version seule pour les anciennes appli)
  update public.rc_players
     set app_ver = left(split_part(coalesce(p_ver, ''), '|', 1), 20),
         app_os = nullif(left(split_part(coalesce(p_ver, ''), '|', 2), 12), ''),
         app_at = now()
   where device = p_device;
  v_ver := split_part(coalesce(p_ver, ''), '|', 1);
  -- 1.0.24 et 1.0.25 sans cadeau propre : donnent le cadeau 1.0.23 à ceux qui ne l'ont pas eu (une seule fois en tout)
  if v_ver in ('1.0.24', '1.0.25') then v_ver := '1.0.23'; end if;
  -- cadeau par version (même JSON que les récompenses → rc__grant) + date de sortie de la version :
  -- seuls les comptes créés avant la sortie le reçoivent (un nouveau compte ne peut pas réclamer les anciens)
  select x.rw, x.out_at into v_rw, v_out from (values
    ('1.0.16', '{"coins":500}'::jsonb, timestamptz '2026-10-21 09:30+00'),
    ('1.0.18', '{"coins":600,"pixels":8,"packs":{"premium":1}}'::jsonb, timestamptz '2026-10-22 06:45+00'),
    ('1.0.23', '{"coins":600,"packs":{"premium":1}}'::jsonb, timestamptz '2026-10-27 08:00+00')
  ) x(ver, rw, out_at) where x.ver = v_ver;
  if v_rw is null then return jsonb_build_object('coins', 0); end if;
  if exists (select 1 from public.rc_players where device = p_device and created_at >= v_out) then
    return jsonb_build_object('coins', 0);
  end if;
  insert into public.rc_upgrade_got (device, ver) values (p_device, v_ver) on conflict do nothing;
  if not found then return jsonb_build_object('coins', 0); end if;
  perform public.rc__grant(p_device, v_rw);
  return jsonb_build_object('coins', coalesce((v_rw->>'coins')::int, 0), 'reward', v_rw);
end $function$;

notify pgrst, 'reload schema';

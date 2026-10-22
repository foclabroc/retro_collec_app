create or replace function public.rc_upgrade_gift(p_device text, p_ver text, p_sig text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare
  v_rw jsonb;
begin
  perform public.rc__check(p_sig, p_device || '|upgrade|' || p_ver);
  if not exists (select 1 from public.rc_players where device = p_device) then raise exception 'joueur inconnu'; end if;
  -- cadeau par version (même JSON que les récompenses → rc__grant) ; une fois par joueur (rc_upgrade_got)
  v_rw := case p_ver
    when '1.0.16' then '{"coins":500}'::jsonb
    when '1.0.18' then '{"coins":600,"pixels":8,"packs":{"premium":1}}'::jsonb
  end;
  if v_rw is null then return jsonb_build_object('coins', 0); end if;
  insert into public.rc_upgrade_got (device, ver) values (p_device, p_ver) on conflict do nothing;
  if not found then return jsonb_build_object('coins', 0); end if;
  perform public.rc__grant(p_device, v_rw);
  return jsonb_build_object('coins', coalesce((v_rw->>'coins')::int, 0), 'reward', v_rw);
end $function$;

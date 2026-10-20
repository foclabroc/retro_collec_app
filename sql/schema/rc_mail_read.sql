create or replace function public.rc_mail_read(p_device text, p_id bigint, p_sig text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare m public.rc_mail; v public.rc_players; i int; g jsonb := '{}'::jsonb;
begin
  perform public.rc__check(p_sig, p_device || '|mailread|' || p_id);
  select * into v from public.rc_players where device = p_device for update;
  if v.device is null then raise exception 'joueur inconnu'; end if;
  select * into m from public.rc_mail x where x.id = p_id
     and (x.device = p_device
          or (x.device is null and x.grp is null)
          or exists (select 1 from public.rc_mail_to t where t.mail_id = x.id and t.device = p_device));
  if m.id is null then raise exception 'message inconnu'; end if;
  insert into public.rc_mail_got (device, mail_id) values (p_device, p_id) on conflict do nothing;
  if found then
    update public.rc_players set coins = coins + m.coins, pixels = pixels + m.pixels where device = p_device;
    for i in 1 .. least(m.packs, 10) loop
      insert into public.rc_gifts (receiver, giver, giver_name, kind) values (p_device, null, 'Pixel Trade', 'premium');
    end loop;
    g := public.rc__grant(p_device, m.reward);
  end if;
  select * into v from public.rc_players where device = p_device;
  return jsonb_build_object('coins', v.coins, 'pixels', v.pixels, 'gain', g);
end $function$;

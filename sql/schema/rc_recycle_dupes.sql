create or replace function public.rc_recycle_dupes(p_device text, p_sig text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare
  gain int := 0; n int := 0; rec record; ev jsonb := '[]'::jsonb;
begin
  perform public.rc__check(p_sig, p_device || '|dupes');
  perform 1 from public.rc_players where device = p_device for update;
  for rec in
    select o.card, o.finish, o.qty, c.rarity from public.rc_owned o join public.rc_cards c on c.id = o.card
     where o.device = p_device and o.qty > 1
  loop
    update public.rc_owned set qty = 1 where device = p_device and card = rec.card and finish = rec.finish;
    gain := gain + public.rc__recycle_value(rec.rarity, rec.finish) * (rec.qty - 1);
    n := n + rec.qty - 1;
  end loop;
  gain := gain * least(coalesce(public.rc__effect('recycle_x'), 1), 5);
  if n > 0 then
    update public.rc_players set fragments = fragments + gain where device = p_device;
    ev := public.rc__bump(p_device, 'recycle', n);
  end if;
  return jsonb_build_object('gain', gain, 'count', n,
                            'fragments', (select fragments from public.rc_players where device = p_device), 'events', ev);
end $function$;

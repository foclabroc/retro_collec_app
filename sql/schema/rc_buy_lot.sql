create or replace function public.rc_buy_lot(p_device text, p_sig text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare v public.rc_players; free boolean; price int := public.rc__lot_price();
begin
  perform public.rc__check(p_sig, p_device || '|lot');
  select * into v from public.rc_players where device = p_device for update;
  if v.device is null then raise exception 'joueur inconnu'; end if;
  free := public.rc__lot_day() and v.lot_free is distinct from public.rc__today();
  if free then
    update public.rc_players set lot_free = public.rc__today(), lots = lots + 5 where device = p_device;
  elsif v.coins < price then
    raise exception 'pas assez de pièces';
  else
    update public.rc_players set coins = coins - price, lots = lots + 5 where device = p_device;
  end if;
  select * into v from public.rc_players where device = p_device;
  return jsonb_build_object('free', free, 'lots', v.lots, 'coins', v.coins);
end $function$;

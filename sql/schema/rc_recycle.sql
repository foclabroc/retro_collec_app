create or replace function public.rc_recycle(p_device text, p_card text, p_finish integer, p_qty integer, p_sig text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare
  total int; r int; gain int; ev jsonb := '[]'::jsonb;
begin
  perform public.rc__check(p_sig, p_device || '|recycle|' || p_card || '|' || p_finish || '|' || p_qty);
  if p_qty < 1 then raise exception 'quantité invalide'; end if;
  perform 1 from public.rc_players where device = p_device for update;
  -- le full art est une carte à part : on garde 1 exemplaire normal / brillant / doré ET 1 full art
  select coalesce(sum(qty), 0) into total from public.rc_owned
   where device = p_device and card = p_card and (finish = 3) = (p_finish = 3);
  if total - p_qty < 1 then raise exception 'dernier exemplaire'; end if;
  if not public.rc__take(p_device, p_card, p_finish, p_qty) then raise exception 'pas assez d''exemplaires'; end if;
  select rarity into r from public.rc_cards where id = p_card;
  gain := public.rc__recycle_value(r, p_finish) * p_qty * least(coalesce(public.rc__effect('recycle_x'), 1), 5);
  update public.rc_players set coins = coins + gain where device = p_device;
  ev := public.rc__bump(p_device, 'recycle', p_qty);
  perform public.rc__rescore(p_device);
  return jsonb_build_object('gain', gain, 'coins', (select coins from public.rc_players where device = p_device), 'events', ev);
end $function$;

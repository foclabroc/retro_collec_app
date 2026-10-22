CREATE OR REPLACE FUNCTION public.rc_market_add(p_device text, p_card text, p_finish integer, p_price integer, p_sig text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare v_id bigint;
begin
  perform public.rc__check(p_sig, p_device || '|sell|' || p_card || '|' || p_finish || '|' || p_price);
  perform public.rc__not_new(p_device);
  perform public.rc__not_blocked(p_device);
  perform 1 from public.rc_players where device = p_device for update;
  if (select count(*) from public.rc_market where seller = p_device and buyer is null) >= 12 then
    raise exception 'trop de lots';
  end if;
  if not public.rc__take(p_device, p_card, p_finish, 1) then raise exception 'carte non possédée'; end if;
  insert into public.rc_market (seller, card, finish, price) values (p_device, p_card, p_finish, p_price)
  returning rc_market.id into v_id;
  perform public.rc__rescore(p_device);
  return v_id;
end $function$

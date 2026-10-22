CREATE OR REPLACE FUNCTION public.rc_trade_offer(p_device text, p_to_pid text, p_give text, p_want text, p_sig text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare v_to text; v_id bigint; ng int; nw int;
begin
  perform public.rc__check(p_sig, p_device || '|offer|' || p_to_pid || '|' || coalesce(p_give, '') || '|' || coalesce(p_want, ''));
  perform public.rc__not_new(p_device);
  perform public.rc__not_blocked(p_device);
  select device into v_to from public.rc_players where pid = p_to_pid;
  if v_to is null then raise exception 'joueur inconnu'; end if;
  if v_to = p_device then raise exception 'pas avec toi-même'; end if;
  select coalesce(sum(n), 0) into ng from public.rc__items(p_give);
  select coalesce(sum(n), 0) into nw from public.rc__items(p_want);
  if ng > 5 or nw > 5 or ng + nw = 0 then raise exception 'échange invalide'; end if;
  if exists (select 1 from public.rc__items(p_give) i where not exists (select 1 from public.rc_cards c where c.id = i.card))
     or exists (select 1 from public.rc__items(p_want) i where not exists (select 1 from public.rc_cards c where c.id = i.card)) then
    raise exception 'carte inconnue';
  end if;
  if not public.rc__has(p_device, p_give) then raise exception 'tu ne possèdes pas ces cartes'; end if;
  if (select count(*) from public.rc_trades where sender = p_device and status = 'pending') >= 10 then
    raise exception 'trop d''échanges en attente';
  end if;
  insert into public.rc_trades (sender, receiver, give, want) values (p_device, v_to, coalesce(p_give, ''), coalesce(p_want, ''))
  returning rc_trades.id into v_id;
  return v_id;
end $function$

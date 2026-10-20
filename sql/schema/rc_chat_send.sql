CREATE OR REPLACE FUNCTION public.rc_chat_send(p_device text, p_msg text, p_sig text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare v public.rc_players; m text; new_id bigint;
begin
  perform public.rc__check(p_sig, p_device || '|chat|' || coalesce(p_msg, ''));
  select * into v from public.rc_players where device = p_device for update;
  if v.device is null then raise exception 'joueur inconnu'; end if;
  if exists (select 1 from public.rc_chat_bans where device = p_device and (until is null or until > now())) then raise exception 'chat interdit'; end if;
  m := trim(coalesce(p_msg, ''));
  if m = '' then raise exception 'message vide'; end if;
  if char_length(m) > 120 then raise exception 'message trop long'; end if;
  if v.chat_last is not null and v.chat_last > now() - interval '10 seconds' then raise exception 'attends un peu'; end if;
  m := public.rc__chat_clean(m);
  insert into public.rc_chat (device, msg) values (p_device, m) returning id into new_id;
  update public.rc_players set chat_last = now(), chat_seen = greatest(chat_seen, new_id) where device = p_device;
  -- on ne garde que les 200 derniers
  delete from public.rc_chat where id <= new_id - 200;
  delete from public.rc_chat_reports where msg_id <= new_id - 200;
  return new_id;
end $function$

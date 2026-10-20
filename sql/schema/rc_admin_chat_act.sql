CREATE OR REPLACE FUNCTION public.rc_admin_chat_act(p_device text, p_sig text, p_id bigint, p_act text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare dev text;
begin
  perform public.rc__admin(p_device, p_sig, 'chatact|' || p_id || '|' || coalesce(p_act, ''));
  select device into dev from public.rc_chat where id = p_id;
  if dev is null then raise exception 'message introuvable'; end if;
  if p_act = 'hide' then
    update public.rc_chat set hidden = true where id = p_id;
  elsif p_act = 'show' then
    update public.rc_chat set hidden = false, reports = 0 where id = p_id;
    delete from public.rc_chat_reports where msg_id = p_id;
  elsif p_act = 'ban' then
    delete from public.rc_chat_bans where device = dev;
    insert into public.rc_chat_bans (device, until) values (dev, now() + interval '24 hours');
    update public.rc_chat set hidden = true where id = p_id;
  elsif p_act = 'unban' then
    delete from public.rc_chat_bans where device = dev;
  else
    raise exception 'action inconnue';
  end if;
  return true;
end $function$

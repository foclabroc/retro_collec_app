CREATE OR REPLACE FUNCTION public.rc_chat_report(p_device text, p_id bigint, p_sig text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  perform public.rc__check(p_sig, p_device || '|report|' || p_id);
  if not exists (select 1 from public.rc_players where device = p_device) then raise exception 'joueur inconnu'; end if;
  insert into public.rc_chat_reports (msg_id, device) values (p_id, p_device) on conflict do nothing;
  if found then
    update public.rc_chat set reports = reports + 1, hidden = hidden or reports + 1 >= 3
     where id = p_id and device <> p_device;
  end if;
  return true;
end $function$

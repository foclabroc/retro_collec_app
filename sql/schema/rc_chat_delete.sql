create or replace function public.rc_chat_delete(p_device text, p_id bigint, p_sig text)
 returns boolean
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
begin
  perform public.rc__check(p_sig, p_device || '|chatdel|' || p_id);
  -- seulement mon propre message ; masqué (et plus supprimé) pour garder la trace côté admin
  update public.rc_chat set hidden = true where id = p_id and device = p_device and not hidden;
  return found;
end $function$;

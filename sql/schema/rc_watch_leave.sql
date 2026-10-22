create or replace function public.rc_watch_leave(p_device text, p_game text, p_id bigint, p_sig text)
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
begin
  perform public.rc__check(p_sig, p_device || '|wleave|' || p_game || '|' || p_id);
  delete from public.rc_watch where game = p_game and gid = p_id and device = p_device;
  if found then
    perform public.rc__watch_send(p_game, p_id, 'watchers',
      jsonb_build_object('game', p_game, 'gid', p_id, 'list', public.rc__watch_list(p_game, p_id)));
  end if;
end $function$;

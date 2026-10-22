create or replace function public.rc_watch_react(p_device text, p_game text, p_id bigint, p_e text, p_sig text)
 returns boolean
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v record;
begin
  perform public.rc__check(p_sig, p_device || '|wreact|' || p_game || '|' || p_id || '|' || p_e);
  if p_e not in ('👏', '🔥', '😂', '😮', '😱', '👍', '💀', '🎉', '😭', '🤯') then return false; end if;
  update public.rc_watch set react_at = now(), seen_at = now()
   where game = p_game and gid = p_id and device = p_device
     and (react_at is null or react_at < now() - interval '1.5 seconds');
  if not found then return false; end if;
  select pid, name, avatar into v from public.rc_players where device = p_device;
  perform public.rc__watch_send(p_game, p_id, 'wreact',
    jsonb_build_object('game', p_game, 'gid', p_id, 'pid', v.pid, 'name', v.name, 'avatar', v.avatar, 'e', p_e));
  return true;
end $function$;

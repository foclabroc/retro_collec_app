create or replace function public.rc_cab_set_game(p_device text, p_game text, p_sig text)
 returns boolean
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v public.rc_players;
begin
  perform public.rc__check(p_sig, p_device || '|cabgame|' || coalesce(p_game, ''));
  if p_game is null or p_game not in ('snake', 'bricks', 'dodge') then raise exception 'jeu inconnu'; end if;
  select * into v from public.rc_players where device = p_device for update;
  if v.device is null then raise exception 'joueur inconnu'; end if;
  if public.rc__cab_game(v.cab_game, v.pid) = p_game then
    update public.rc_players set cab_game = p_game where device = p_device and cab_game is null;
    return false;
  end if;
  update public.rc_players set cab_game = p_game where device = p_device;
  delete from public.rc_cab_best where owner = p_device;
  perform public.rc__rt_safe('rc_all', 'cab', jsonb_build_object('pid', v.pid));
  return true;
end $function$;

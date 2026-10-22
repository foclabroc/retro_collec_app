create or replace function public.rc_watch_join(p_device text, p_game text, p_id bigint, p_sig text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare isnew boolean;
begin
  perform public.rc__check(p_sig, p_device || '|wjoin|' || p_game || '|' || p_id);
  if not exists (select 1 from public.rc__watch_game(p_game, p_id)) then
    return jsonb_build_object('list', '[]'::jsonb, 'over', true);
  end if;
  -- un joueur de la partie ne compte pas comme spectateur
  if exists (select 1 from public.rc__watch_game(p_game, p_id) x where p_device in (x.p1, x.p2)) then
    return jsonb_build_object('list', public.rc__watch_list(p_game, p_id));
  end if;
  select not exists (select 1 from public.rc_watch w where w.game = p_game and w.gid = p_id and w.device = p_device
                        and w.seen_at > now() - interval '50 seconds') into isnew;
  insert into public.rc_watch (game, gid, device) values (p_game, p_id, p_device)
  on conflict (game, gid, device) do update set seen_at = now();
  if isnew then
    perform public.rc__watch_send(p_game, p_id, 'watchers',
      jsonb_build_object('game', p_game, 'gid', p_id, 'list', public.rc__watch_list(p_game, p_id)));
  end if;
  -- ménage : spectateurs de parties finies depuis longtemps
  if random() < 0.05 then delete from public.rc_watch where seen_at < now() - interval '1 day'; end if;
  return jsonb_build_object('list', public.rc__watch_list(p_game, p_id));
end $function$;

create or replace function public.rc_rj_answer(p_device text, p_id bigint, p_accept boolean, p_sig text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare g public.rc_rj;
begin
  perform public.rc__check(p_sig, p_device || '|rjans|' || p_id || '|' || case when p_accept then 1 else 0 end);
  perform public.rc__rj_settle(p_id);
  select * into g from public.rc_rj where id = p_id for update;
  if g.id is null or p_device not in (g.p1, g.p2) then raise exception 'partie inconnue'; end if;
  if g.status <> 'invite' then raise exception 'invitation expirée'; end if;
  if not p_accept then
    update public.rc_rj set status = 'done', reason = case when p_device = g.p1 then 'cancelled' else 'declined' end, move_at = now()
     where id = p_id;
  else
    if p_device <> g.p2 then raise exception 'partie inconnue'; end if;
    perform public.rc__not_blocked(p_device);
    if public.rc__duel_busy(p_device) then raise exception 'tu es déjà en partie'; end if;
    if public.rc__duel_busy(g.p1) then raise exception 'joueur déjà en partie'; end if;
    if exists (select 1 from public.rc_players where device = g.p1 and blocked) then raise exception 'joueur indisponible'; end if;
    update public.rc_players set seen_at = now() where device = p_device;
    -- départ dans 6 s : le temps d'ouvrir la partie des deux côtés + 3, 2, 1
    update public.rc_rj set status = 'playing', seed = floor(random() * 2147483646)::int + 1,
           start_at = now() + interval '6 seconds', end_at = now() + interval '126 seconds', move_at = now()
     where id = p_id;
  end if;
  select * into g from public.rc_rj where id = p_id;
  return public.rc__rj_json(g, p_device) || jsonb_build_object('coins', (select coins from public.rc_players where device = p_device));
end $function$;

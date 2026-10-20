create or replace function public.rc_trade_answer(p_device text, p_id bigint, p_accept boolean, p_sig text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare
  t public.rc_trades; it record; ev jsonb := '[]'::jsonb;
begin
  perform public.rc__check(p_sig, p_device || '|answer|' || p_id || '|' || p_accept);
  select * into t from public.rc_trades x where x.id = p_id and x.receiver = p_device and x.status = 'pending' for update;
  if t.id is null then raise exception 'échange introuvable'; end if;
  if p_accept then
    perform public.rc__not_blocked(t.sender);
    perform public.rc__not_blocked(t.receiver);
  end if;
  if not p_accept then
    update public.rc_trades set status = 'refused', done_at = now() where id = t.id;
    return jsonb_build_object('status', 'refused');
  end if;
  -- verrouille les deux joueurs dans un ordre fixe (pas d'interblocage)
  perform 1 from public.rc_players where device in (t.sender, t.receiver) order by device for update;
  if not public.rc__has(t.sender, t.give) or not public.rc__has(t.receiver, t.want) then
    update public.rc_trades set status = 'failed', done_at = now() where id = t.id;
    return jsonb_build_object('status', 'failed');
  end if;
  for it in select * from public.rc__items(t.give) loop
    perform public.rc__take(t.sender, it.card, it.finish, it.n);
    perform public.rc__give(t.receiver, it.card, it.finish, it.n);
  end loop;
  for it in select * from public.rc__items(t.want) loop
    perform public.rc__take(t.receiver, it.card, it.finish, it.n);
    perform public.rc__give(t.sender, it.card, it.finish, it.n);
  end loop;
  update public.rc_trades set status = 'accepted', done_at = now() where id = t.id;
  ev := ev || public.rc__bump(p_device, 'trade', 1) || public.rc__milestones(p_device);
  perform public.rc__bump(t.sender, 'trade', 1);
  perform public.rc__ev_bump(t.sender, 'trades', 1);    -- défi : échanges
  perform public.rc__ev_bump(t.receiver, 'trades', 1);
  perform public.rc__milestones(t.sender);
  perform public.rc__rescore(t.sender);
  perform public.rc__rescore(t.receiver);
  return jsonb_build_object('status', 'accepted', 'events', ev);
end $function$;

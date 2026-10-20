CREATE OR REPLACE FUNCTION public.rc_bs_answer(p_device text, p_id bigint, p_accept boolean, p_sig text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare g public.rc_bs; c1 bigint; c2 bigint;
begin
  perform public.rc__check(p_sig, p_device || '|bsans|' || p_id || '|' || case when p_accept then 1 else 0 end);
  perform public.rc__bs_settle(p_id);
  select * into g from public.rc_bs where id = p_id for update;
  if g.id is null or p_device not in (g.p1, g.p2) then raise exception 'partie inconnue'; end if;
  if g.status <> 'invite' then raise exception 'invitation expirée'; end if;
  if not p_accept then
    update public.rc_bs set status = 'done', reason = case when p_device = g.p1 then 'cancelled' else 'declined' end where id = p_id;
  else
    if p_device <> g.p2 then raise exception 'partie inconnue'; end if;
    select coins into c1 from public.rc_players where device = g.p1 for update;
    select coins into c2 from public.rc_players where device = g.p2 for update;
    if c2 < g.stake then raise exception 'pas assez de pièces'; end if;
    if c1 < g.stake then raise exception 'adversaire sans pièces'; end if;
    update public.rc_players set coins = coins - g.stake where device in (g.p1, g.p2);
    update public.rc_players set seen_at = now() where device = p_device;
    update public.rc_bs set status = 'setup', move_at = now() where id = p_id;
  end if;
  return public.rc__bs_out(p_id, p_device);
end $function$

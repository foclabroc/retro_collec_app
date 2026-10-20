CREATE OR REPLACE FUNCTION public.rc_bs_place(p_device text, p_id bigint, p_fleet jsonb, p_sig text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare g public.rc_bs; side int;
begin
  perform public.rc__check(p_sig, p_device || '|bsplace|' || p_id);
  perform public.rc__bs_settle(p_id);
  select * into g from public.rc_bs where id = p_id for update;
  if g.id is null or p_device not in (g.p1, g.p2) then raise exception 'partie inconnue'; end if;
  if g.status <> 'setup' then raise exception 'flotte déjà placée'; end if;
  if not public.rc__bs_valid(p_fleet) then raise exception 'flotte invalide'; end if;
  side := case when g.p1 = p_device then 1 else 2 end;
  if (side = 1 and g.fleet1 is not null) or (side = 2 and g.fleet2 is not null) then raise exception 'flotte déjà placée'; end if;
  if side = 1 then update public.rc_bs set fleet1 = p_fleet where id = p_id;
  else update public.rc_bs set fleet2 = p_fleet where id = p_id; end if;
  update public.rc_players set seen_at = now() where device = p_device;
  update public.rc_bs set status = 'playing', turn = 1, move_at = now()
   where id = p_id and fleet1 is not null and fleet2 is not null;
  return public.rc__bs_out(p_id, p_device);
end $function$

CREATE OR REPLACE FUNCTION public.rc_bs_shoot(p_device text, p_id bigint, p_cell integer, p_sig text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare g public.rc_bs; side int;
begin
  perform public.rc__check(p_sig, p_device || '|bsshoot|' || p_id || '|' || p_cell);
  perform public.rc__bs_settle(p_id);
  select * into g from public.rc_bs where id = p_id for update;
  if g.id is null or p_device not in (g.p1, g.p2) then raise exception 'partie inconnue'; end if;
  if g.status <> 'playing' then raise exception 'partie terminée'; end if;
  side := case when g.p1 = p_device then 1 else 2 end;
  if g.turn <> side then raise exception 'pas ton tour'; end if;
  if p_cell is null or p_cell < 0 or p_cell > 63 then raise exception 'case invalide'; end if;
  if substr(case when side = 1 then g.shots1 else g.shots2 end, p_cell + 1, 1) <> '0' then raise exception 'case déjà visée'; end if;
  if side = 1 then update public.rc_bs set late1 = 0 where id = p_id; else update public.rc_bs set late2 = 0 where id = p_id; end if;
  update public.rc_players set seen_at = now() where device = p_device;
  perform public.rc__bs_fire(p_id, side, p_cell, now());
  return public.rc__bs_out(p_id, p_device);
end $function$

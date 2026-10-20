CREATE OR REPLACE FUNCTION public.rc_c4_play(p_device text, p_id bigint, p_col integer, p_sig text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare g public.rc_c4; side int; r int; pos int; b text;
begin
  perform public.rc__check(p_sig, p_device || '|c4play|' || p_id || '|' || p_col);
  perform public.rc__c4_settle(p_id);
  select * into g from public.rc_c4 where id = p_id for update;
  if g.id is null or p_device not in (g.p1, g.p2) then raise exception 'partie inconnue'; end if;
  if g.status <> 'playing' then raise exception 'partie terminée'; end if;
  side := case when g.p1 = p_device then 1 else 2 end;
  if g.turn <> side then raise exception 'pas ton tour'; end if;
  if p_col is null or p_col < 0 or p_col > 6 then raise exception 'colonne invalide'; end if;
  r := 5;
  while r >= 0 and substr(g.board, r * 7 + p_col + 1, 1) <> '0' loop r := r - 1; end loop;
  if r < 0 then raise exception 'colonne pleine'; end if;
  pos := r * 7 + p_col + 1;
  b := overlay(g.board placing side::text from pos for 1);
  update public.rc_c4 set board = b, moves = moves + 1, last_col = p_col where id = p_id;
  update public.rc_players set seen_at = now() where device = p_device;
  if public.rc__c4_win(b, r, p_col, side::text) then
    perform public.rc__c4_finish(p_id, side, 'win');
  elsif g.moves + 1 >= 42 then
    perform public.rc__c4_finish(p_id, 0, 'draw');
  else
    update public.rc_c4 set turn = 3 - side, move_at = now() where id = p_id;
  end if;
  select * into g from public.rc_c4 where id = p_id;
  return public.rc__c4_json(g, p_device) || jsonb_build_object('coins', (select coins from public.rc_players where device = p_device));
end $function$

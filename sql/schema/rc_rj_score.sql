create or replace function public.rc_rj_score(p_device text, p_id bigint, p_h integer, p_dead boolean, p_sig text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare g public.rc_rj; side int; cap int; sec numeric;
begin
  perform public.rc__check(p_sig, p_device || '|rjsc|' || p_id || '|' || p_h || '|' || case when p_dead then 1 else 0 end);
  select * into g from public.rc_rj where id = p_id for update;
  if g.id is null or p_device not in (g.p1, g.p2) then raise exception 'partie inconnue'; end if;
  side := case when g.p1 = p_device then 1 else 2 end;
  if g.status = 'playing' and now() <= g.end_at + interval '5 seconds'
     and (case when side = 1 then g.dead1 else g.dead2 end) is null then
    sec := greatest(0, extract(epoch from (least(now(), g.end_at) - g.start_at)));
    -- Rétro Jump : 70 points par seconde ; course : 24 mètres par seconde (vitesse max 22)
    cap := case when g.kind = 'run' then 100 + floor(24 * sec)::int else 60 + floor(70 * sec)::int end;
    p_h := least(greatest(coalesce(p_h, 0), 0), cap);
    if side = 1 then
      update public.rc_rj set h1 = greatest(h1, p_h), seen1 = now(), moves = moves + 1,
             dead1 = case when p_dead then now() end, move_at = now() where id = p_id;
    else
      update public.rc_rj set h2 = greatest(h2, p_h), seen2 = now(), moves = moves + 1,
             dead2 = case when p_dead then now() end, move_at = now() where id = p_id;
    end if;
  end if;
  update public.rc_players set seen_at = now()
   where device = p_device and (seen_at is null or seen_at < now() - interval '30 seconds');
  perform public.rc__rj_settle(p_id);
  select * into g from public.rc_rj where id = p_id;
  return public.rc__rj_json(g, p_device);
end $function$;

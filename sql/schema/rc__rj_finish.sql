create or replace function public.rc__rj_finish(p_id bigint, p_winner integer, p_reason text)
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare g public.rc_rj; ok boolean; m int := least(coalesce(public.rc__effect('duel_x'), 1), 5);
begin
  select * into g from public.rc_rj where id = p_id;
  if g.status <> 'playing' then return; end if;
  ok := g.moves > 0 and public.rc__duel_paid(g.p1, g.p2);
  update public.rc_rj set status = 'done', winner = p_winner, reason = p_reason, paid = ok, move_at = now() where id = p_id;
  if not ok then return; end if;  -- partie amicale (ou personne n'a joué) : pas de gains
  if p_winner in (1, 2) then perform public.rc__wbump(case when p_winner = 1 then g.p1 else g.p2 end, 'win', 1); end if;
  perform public.rc__wbump(g.p1, 'play', 1);
  perform public.rc__wbump(g.p2, 'play', 1);
  if p_winner = 0 then
    update public.rc_players set coins = coins + 10 * m where device in (g.p1, g.p2);
  else
    update public.rc_players set coins = coins + 150 * m, pixels = pixels + 1
     where device = case when p_winner = 1 then g.p1 else g.p2 end;
    update public.rc_players set coins = coins + 10 * m
     where device = case when p_winner = 1 then g.p2 else g.p1 end;
  end if;
end $function$;

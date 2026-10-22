create or replace function public.rc__tour_game_done()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare m public.rc_tour_matches; st text; dev text; need int;
begin
  select * into m from public.rc_tour_matches where id = new.tmatch for update;
  if m.id is null or m.status <> 'play' or m.game_id is distinct from new.id then return null; end if;
  select status into st from public.rc_tour where id = m.tid;
  if st is distinct from 'running' then return null; end if;
  if new.winner in (1, 2) then
    dev := case when new.winner = 1 then new.p1 else new.p2 end;
    if dev = m.p1 then m.w1 := m.w1 + 1; else m.w2 := m.w2 + 1; end if;
    update public.rc_tour_matches set w1 = m.w1, w2 = m.w2 where id = m.id;
  end if;
  need := (m.best + 1) / 2;
  if m.w1 >= need or m.w2 >= need then
    update public.rc_tour_matches set status = 'done', reason = 'win',
           winner = case when m.w1 >= need then m.p1 else m.p2 end
     where id = m.id;
    perform public.rc__tour_after(m.tid);
  else
    perform public.rc__tour_game(m.id);  -- match nul ou manche suivante
  end if;
  return null;
end $function$;

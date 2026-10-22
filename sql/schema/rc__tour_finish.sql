create or replace function public.rc__tour_finish(p_tid bigint)
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare t public.rc_tour; f public.rc_tour_matches; w text; s text; d text; a int;
begin
  select * into t from public.rc_tour where id = p_tid;
  select * into f from public.rc_tour_matches where tid = p_tid and round = t.rounds and slot = 0;
  w := f.winner;
  s := case when f.winner = f.p1 then f.p2 else f.p1 end;
  update public.rc_tour_players set place = 1 where tid = p_tid and device = w;
  if s is not null then update public.rc_tour_players set place = 2 where tid = p_tid and device = s; end if;
  -- lots fixes
  perform public.rc__grant(w, coalesce(t.lots->'1', '{}'::jsonb));
  if s is not null then perform public.rc__grant(s, coalesce(t.lots->'2', '{}'::jsonb)); end if;
  if t.rounds >= 2 then
    for d in select case when m.winner = m.p1 then m.p2 else m.p1 end
               from public.rc_tour_matches m where m.tid = p_tid and m.round = t.rounds - 1 loop
      if d is not null then
        update public.rc_tour_players set place = 3 where tid = p_tid and device = d;
        perform public.rc__grant(d, coalesce(t.lots->'3', '{}'::jsonb));
      end if;
    end loop;
  end if;
  -- cagnotte
  if t.pot > 0 then
    if t.split >= 100 or s is null then
      update public.rc_players set coins = coins + t.pot where device = w;
    else
      a := floor(t.pot * t.split / 100.0);
      update public.rc_players set coins = coins + a where device = w;
      update public.rc_players set coins = coins + (t.pot - a) where device = s;
    end if;
  end if;
  perform public.rc__tbump(w, 'tourney', 1);
  begin
    perform public.rc__feed_put(w, 'tour', s, null, null, t.game, t.pot, t.name);
  exception when others then null;
  end;
  update public.rc_tour set status = 'done', winner = w, second = s, ended_at = now() where id = p_tid;
end $function$;

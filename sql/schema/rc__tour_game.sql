create or replace function public.rc__tour_game(p_mid bigint)
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare m public.rc_tour_matches; jeu text; a text; b text; gid bigint; d interval;
begin
  select * into m from public.rc_tour_matches where id = p_mid;
  select game into jeu from public.rc_tour where id = m.tid;
  if random() < 0.5 then a := m.p1; b := m.p2; else a := m.p2; b := m.p1; end if;
  -- manche suivante : 15 s pour revenir sur la partie
  d := case when m.game_id is null then interval '0' else interval '15 seconds' end;
  if jeu = 'c4' then
    insert into public.rc_c4 (p1, p2, mode, stake, status, turn, move_at, tmatch)
    values (a, b, 'live', 0, 'playing', 1, now() + d, m.id) returning id into gid;
  else
    insert into public.rc_bs (p1, p2, mode, stake, status, move_at, tmatch)
    values (a, b, 'live', 0, 'setup', now() + d, m.id) returning id into gid;
  end if;
  update public.rc_tour_matches set status = 'play', game_id = gid where id = p_mid;
end $function$;

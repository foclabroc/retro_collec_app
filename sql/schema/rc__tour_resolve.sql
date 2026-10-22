create or replace function public.rc__tour_resolve(p_mid bigint)
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare m public.rc_tour_matches; w text; why text;
begin
  select * into m from public.rc_tour_matches where id = p_mid for update;
  if m.id is null or m.status <> 'wait' or now() <= m.start_at + interval '3 minutes' then return; end if;
  if m.ready1 is not null and m.ready2 is null then w := m.p1; why := 'forfeit';
  elsif m.ready2 is not null and m.ready1 is null then w := m.p2; why := 'forfeit';
  elsif m.ready1 is null and m.ready2 is null then
    w := case when random() < 0.5 then m.p1 else m.p2 end; why := 'lot';
  else
    perform public.rc__tour_game(p_mid);  -- les deux là (ne devrait pas arriver)
    return;
  end if;
  update public.rc_tour_matches set status = 'done', winner = w, reason = why where id = p_mid;
  perform public.rc__tour_after(m.tid);
end $function$;

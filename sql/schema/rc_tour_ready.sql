create or replace function public.rc_tour_ready(p_device text, p_mid bigint, p_sig text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare m public.rc_tour_matches;
begin
  perform public.rc__check(p_sig, p_device || '|tready|' || p_mid);
  select * into m from public.rc_tour_matches where id = p_mid for update;
  if m.id is null or p_device not in (m.p1, m.p2) then raise exception 'match inconnu'; end if;
  update public.rc_players set seen_at = now() where device = p_device;
  if m.status = 'wait' then
    if now() > m.start_at + interval '3 minutes' then
      perform public.rc__tour_resolve(p_mid);
    else
      if p_device = m.p1 then update public.rc_tour_matches set ready1 = coalesce(ready1, now()) where id = p_mid;
      else update public.rc_tour_matches set ready2 = coalesce(ready2, now()) where id = p_mid; end if;
      select * into m from public.rc_tour_matches where id = p_mid;
      if m.ready1 is not null and m.ready2 is not null then perform public.rc__tour_game(p_mid); end if;
    end if;
  end if;
  return coalesce(public.rc__tour_me(p_device), '{}'::jsonb)
      || jsonb_build_object('match', (select jsonb_build_object('id', x.id, 'status', x.status, 'game_id', x.game_id, 'reason', x.reason,
                                                               'won', x.winner = p_device)
                                        from public.rc_tour_matches x where x.id = p_mid));
end $function$;

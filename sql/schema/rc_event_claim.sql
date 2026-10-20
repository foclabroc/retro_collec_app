create or replace function public.rc_event_claim(p_device text, p_id bigint, p_sig text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare e public.rc_events; v public.rc_players; rw jsonb := '{}'::jsonb; g jsonb; prog int; done int; st jsonb; i int := 0;
begin
  perform public.rc__check(p_sig, p_device || '|event|' || p_id);
  select * into v from public.rc_players where device = p_device for update;
  if v.device is null then raise exception 'joueur inconnu'; end if;
  select * into e from public.rc_events where id = p_id and active;
  if e.id is null then raise exception 'événement inconnu'; end if;
  if not public.rc__ev_live(e) then raise exception 'événement terminé'; end if;

  if e.kind = 'goal' then
    prog := public.rc__ev_progress(p_device, e);
    insert into public.rc_events_prog (device, event_id) values (p_device, p_id) on conflict do nothing;
    select claimed into done from public.rc_events_prog where device = p_device and event_id = p_id for update;
    for st in select value from jsonb_array_elements(e.steps) loop
      i := i + 1;
      if i > done and prog >= coalesce((st->>'n')::int, 0) then
        rw := public.rc__rw_add(rw, jsonb_build_object('coins', coalesce((st->>'coins')::int, 0), 'pixels', coalesce((st->>'pixels')::int, 0)));
        rw := public.rc__rw_add(rw, st->'reward');
        done := i;
      end if;
    end loop;
    if not public.rc__rw_any(rw) then raise exception 'pas de palier à récupérer'; end if;
    update public.rc_events_prog set claimed = done where device = p_device and event_id = p_id;
  else
    rw := public.rc__rw_add(jsonb_build_object('coins', e.coins, 'pixels', e.pixels), e.reward);
    if not public.rc__rw_any(rw) then raise exception 'pas de récompense'; end if;
    insert into public.rc_events_got (device, event_id) values (p_device, p_id) on conflict do nothing;
    if not found then raise exception 'déjà récupéré'; end if;
  end if;

  g := public.rc__grant(p_device, rw);
  select * into v from public.rc_players where device = p_device;
  return jsonb_build_object('coins', v.coins, 'pixels', v.pixels,
                            'gain_coins', coalesce((g->>'coins')::int, 0), 'gain_pixels', coalesce((g->>'pixels')::int, 0), 'gain', g);
end $function$;

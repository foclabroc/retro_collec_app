create or replace function public.rc_admin_event_save(p_device text, p_sig text, p_id bigint, p_data text)
 returns bigint
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare j jsonb; v_id bigint := p_id; k text; v_steps jsonb := '[]'::jsonb; st jsonb;
begin
  perform public.rc__admin(p_device, p_sig, 'evsave|' || coalesce(p_id, 0) || '|' || coalesce(p_data, ''));
  j := p_data::jsonb;
  k := coalesce(j->>'kind', 'info');
  if k not in ('info', 'effect', 'goal') then raise exception 'type inconnu'; end if;
  if trim(coalesce(j->>'title', '')) = '' then raise exception 'titre vide'; end if;
  if k = 'effect' and coalesce(j->>'effect', '') not in
     ('pixels_x2', 'free_fast', 'promo', 'holo_x', 'rare_x', 'recycle_x', 'duel_x', 'lot_free') then
    raise exception 'effet inconnu';
  end if;
  if k = 'effect' and j->>'effect' = 'promo' and coalesce(nullif(j->>'arg', ''), 'all') not in ('all', 'mixte', 'console', 'premium', 'mystery', 'lot') then
    raise exception 'paquet inconnu';
  end if;
  if k = 'effect' and nullif(j->>'effect_value', '') is not null and (j->>'effect_value')::int not between 1 and 90 then
    raise exception 'valeur entre 1 et 90';
  end if;
  if k = 'goal' and coalesce(j->>'goal', '') not in
     ('packs', 'c4_wins', 'bs_wins', 'gamedle', 'sales', 'trades', 'recycle', 'epics', 'gifts_sent', 'quiz', 'console') then
    raise exception 'défi inconnu';
  end if;
  if k = 'goal' and j->>'goal' = 'console' and not exists (select 1 from public.rc_cards where sys = j->>'arg') then
    raise exception 'console inconnue';
  end if;
  if (j->>'ends_at') is not null and (j->>'ends_at')::timestamptz <= (j->>'starts_at')::timestamptz then
    raise exception 'la fin doit être après le début';
  end if;
  if k = 'goal' then
    for st in select value from jsonb_array_elements(coalesce(j->'steps', '[]'::jsonb)) loop
      v_steps := v_steps || jsonb_build_array(jsonb_build_object(
        'n', greatest(coalesce((st->>'n')::int, 0), 1),
        'coins', least(greatest(coalesce((st->>'coins')::int, 0), 0), 100000),
        'pixels', least(greatest(coalesce((st->>'pixels')::int, 0), 0), 1000),
        'reward', public.rc__rw_clean(st->'reward')));
    end loop;
  end if;
  if v_id is null then
    insert into public.rc_events (kind, title, starts_at) values (k, j->>'title', coalesce((j->>'starts_at')::timestamptz, now()))
    returning rc_events.id into v_id;
  end if;
  update public.rc_events set
    kind = k, title = left(trim(j->>'title'), 60), title_en = nullif(trim(coalesce(j->>'title_en', '')), ''),
    body = left(coalesce(j->>'body', ''), 600), body_en = nullif(trim(coalesce(j->>'body_en', '')), ''),
    icon = coalesce(nullif(j->>'icon', ''), '🎉'), color = coalesce(nullif(j->>'color', ''), '#EF9F27'),
    decor = nullif(j->>'decor', ''),
    starts_at = coalesce((j->>'starts_at')::timestamptz, starts_at), ends_at = (j->>'ends_at')::timestamptz,
    coins = case when k = 'info' then least(greatest(coalesce((j->>'coins')::int, 0), 0), 100000) else 0 end,
    pixels = case when k = 'info' then least(greatest(coalesce((j->>'pixels')::int, 0), 0), 1000) else 0 end,
    reward = case when k = 'info' then public.rc__rw_clean(j->'reward') else '{}'::jsonb end,
    arg = case when k = 'effect' and j->>'effect' = 'promo' then coalesce(nullif(j->>'arg', ''), 'all')
               when k = 'goal' and j->>'goal' = 'console' then j->>'arg' end,
    action = nullif(j->>'action', ''),
    effect = case when k = 'effect' then j->>'effect' end,
    effect_value = case when k = 'effect' then nullif(j->>'effect_value', '')::int end,
    goal = case when k = 'goal' then j->>'goal' end,
    steps = v_steps,
    active = coalesce((j->>'active')::boolean, true)
  where rc_events.id = v_id;
  return v_id;
end $function$;

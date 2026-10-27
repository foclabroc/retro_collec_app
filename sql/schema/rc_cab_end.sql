create or replace function public.rc_cab_end(p_device text, p_run bigint, p_score integer, p_sig text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  x public.rc_cab_runs; o public.rc_players; me public.rc_players;
  v_week date := public.rc__cab_week(); v_secs numeric; v_rate int; v_prev int; v_new boolean := false; v_gain int := 0; v_best int;
begin
  perform public.rc__check(p_sig, p_device || '|cabend|' || coalesce(p_run, 0) || '|' || coalesce(p_score, 0));
  select * into x from public.rc_cab_runs where id = p_run for update;
  if x.id is null or x.device <> p_device then raise exception 'partie inconnue'; end if;
  if x.done_at is not null then raise exception 'partie déjà terminée'; end if;
  v_secs := extract(epoch from now() - x.started_at);
  v_rate := case x.game when 'snake' then 250 when 'bricks' then 450 else 120 end; -- points par seconde au maximum
  if p_score is null or p_score < 0 or p_score > v_rate * v_secs + 200 or v_secs > 3 * 3600 then
    update public.rc_cab_runs set done_at = now(), score = 0 where id = x.id;
    raise exception 'score refusé';
  end if;
  update public.rc_cab_runs set done_at = now(), score = p_score where id = x.id;
  select * into o from public.rc_players where device = x.owner;
  select * into me from public.rc_players where device = p_device for update;
  -- la partie compte si la borne a toujours le même jeu
  if public.rc__cab_game(o.cab_game, o.pid) = x.game and p_score > 0 then
    select r.score into v_prev from public.rc__cab_rec(o.device, x.game) r;
    insert into public.rc_cab_best (owner, game, week, device, score, at)
    values (o.device, x.game, v_week, p_device, p_score, now())
    on conflict (owner, game, week, device) do update set score = excluded.score, at = excluded.at
      where public.rc_cab_best.score < excluded.score;
    v_new := p_score > coalesce(v_prev, 0);
    if v_new and o.device <> p_device and not me.blocked then
      insert into public.rc_cab_paid (owner, device, day) values (o.device, p_device, public.rc__today())
      on conflict do nothing;
      if found then
        v_gain := 20;
        update public.rc_players set coins = coins + v_gain, updated_at = now() where device = p_device returning coins into me.coins;
      end if;
    end if;
    if v_new then
      perform public.rc__rt_safe('rc_all', 'cab', jsonb_build_object('pid', o.pid));
      if o.device <> p_device then
        perform public.rc__rt_safe(public.rc__rt_topic(o.device), 'me',
          jsonb_build_object('k', 'cabrec', 'name', me.name, 'game', x.game, 'score', p_score));
      end if;
    end if;
  end if;
  select b.score into v_best from public.rc_cab_best b
   where b.owner = o.device and b.game = x.game and b.week = v_week and b.device = p_device;
  return jsonb_build_object('score', p_score, 'best', v_best, 'newrec', v_new, 'gain', v_gain, 'coins', me.coins,
    'rec', (select r.score from public.rc__cab_rec(o.device, x.game) r));
end $function$;

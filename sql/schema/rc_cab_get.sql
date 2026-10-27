create or replace function public.rc_cab_get(p_device text, p_pid text, p_sig text)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to 'public'
as $function$
declare o public.rc_players; v_game text; v_week date := public.rc__cab_week(); r jsonb;
begin
  perform public.rc__check(p_sig, p_device || '|cab|' || coalesce(p_pid, ''));
  select * into o from public.rc_players where pid = p_pid;
  if o.device is null then raise exception 'joueur inconnu'; end if;
  v_game := public.rc__cab_game(o.cab_game, o.pid);
  r := jsonb_build_object(
    'pid', o.pid, 'name', o.name, 'game', v_game, 'me', o.device = p_device,
    'top', (select coalesce(jsonb_agg(jsonb_build_object('pid', p.pid, 'name', p.name, 'avatar', p.avatar, 'score', t.score)
                                      order by t.score desc, t.at), '[]'::jsonb)
              from (select b.device, b.score, b.at from public.rc_cab_best b
                     where b.owner = o.device and b.game = v_game and b.week = v_week
                     order by b.score desc, b.at limit 5) t
              join public.rc_players p on p.device = t.device),
    'best', (select b.score from public.rc_cab_best b
              where b.owner = o.device and b.game = v_game and b.week = v_week and b.device = p_device),
    'paid', exists (select 1 from public.rc_cab_paid x where x.owner = o.device and x.device = p_device and x.day = public.rc__today()));
  if o.device = p_device then
    r := r || jsonb_build_object(
      'plays', (select count(*) from public.rc_cab_runs x
                 where x.owner = p_device and x.device <> p_device and x.started_at >= v_week::timestamp at time zone 'Europe/Paris'),
      'comm', (select count(*) from public.rc_cab_runs x
                 where x.owner = p_device and x.comm and x.started_at >= v_week::timestamp at time zone 'Europe/Paris'),
      'held', (select count(*) from public.rc_players p
                where p.device <> p_device
                  and (select c.device from public.rc__cab_rec(p.device, public.rc__cab_game(p.cab_game, p.pid)) c) = p_device));
  end if;
  return r;
end $function$;

create or replace function public.rc_bs_watch(p_id bigint)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare g public.rc_bs;
begin
  perform public.rc__bs_settle(p_id);
  select * into g from public.rc_bs where id = p_id and mode = 'live' and status in ('setup', 'playing', 'done');
  if g.id is null then raise exception 'partie introuvable'; end if;
  -- vue du joueur 1 ; sa flotte : seulement les consoles coulées (toute la flotte à la fin)
  return (public.rc__bs_json(g, g.p1) - 'msg' - 'reply')
         || jsonb_build_object(
              'watch', true, 'me', public.rc__pinfo(g.p1), 'emo_me', g.emo1, 'emo_me_at', g.emo1_at,
              'me_ready', g.fleet1 is not null,
              'my_fleet', case when g.status = 'done' then coalesce(g.fleet1, '[]'::jsonb)
                               else public.rc__bs_sunk(g.fleet1, coalesce(g.shots2, '')) end,
              'turn', case when g.status = 'setup' then 0 else g.turn end);
end $function$;

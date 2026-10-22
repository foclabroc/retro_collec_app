create or replace function public.rc__rt_unwatch(p_player text, p_watch text)
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare r record;
begin
  for r in delete from public.rc_watch w
            where w.seen_at > now() - interval '1 hour'
              and public.rc__rt_watch_topic(w.game, w.gid) = p_watch
              and public.rc__rt_topic(w.device) = p_player
           returning w.game, w.gid loop
    perform public.rc__watch_send(r.game, r.gid, 'watchers',
      jsonb_build_object('game', r.game, 'gid', r.gid, 'list', public.rc__watch_list(r.game, r.gid)));
  end loop;
end $function$

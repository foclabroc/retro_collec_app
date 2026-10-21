create or replace function public.rc__rt_duel()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare msg jsonb;
begin
  msg := jsonb_build_object('game', tg_argv[0], 'gid', new.id, 'status', new.status);
  begin
    if new.p1 is not null then perform public.rc__rt_send(public.rc__rt_topic(new.p1), 'duel', msg); end if;
    if new.p2 is not null then perform public.rc__rt_send(public.rc__rt_topic(new.p2), 'duel', msg); end if;
    if new.mode = 'live' then
      -- spectateurs de cette partie
      perform public.rc__rt_send(public.rc__rt_watch_topic(tg_argv[0], new.id), 'duel', msg);
      -- liste des parties en cours (début, fin)
      if tg_op = 'INSERT' or new.status is distinct from old.status then
        perform public.rc__rt_send('rc_all', 'duels', '{}'::jsonb);
      end if;
    end if;
  exception when others then
    null; -- relais indisponible : le polling de secours prend le relais
  end;
  return null;
end $function$;

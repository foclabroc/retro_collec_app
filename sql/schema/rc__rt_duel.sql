create or replace function public.rc__rt_duel()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare msg jsonb;
begin
  -- clé 'gid' (et pas 'id' : realtime.send s'en servirait comme identifiant du message)
  msg := jsonb_build_object('game', tg_argv[0], 'gid', new.id, 'status', new.status);
  begin
    if new.p1 is not null then perform realtime.send(msg, 'duel', public.rc__rt_topic(new.p1), false); end if;
    if new.p2 is not null then perform realtime.send(msg, 'duel', public.rc__rt_topic(new.p2), false); end if;
  exception when others then
    null; -- Realtime indisponible : le polling de secours prend le relais
  end;
  return null;
end $function$;

CREATE OR REPLACE FUNCTION public.rc__ev_players_trg()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare m int; e public.rc_events;
begin
  if new.packs > old.packs then
    if new.pixels > old.pixels then
      m := public.rc__effect('pixels_x2');
      if m is not null and m > 1 then new.pixels := old.pixels + (new.pixels - old.pixels) * m; end if;
    end if;
    for e in select * from public.rc_events where kind = 'goal' and goal = 'packs' and public.rc__ev_live(rc_events) loop
      insert into public.rc_events_prog (device, event_id, n) values (new.device, e.id, new.packs - old.packs)
        on conflict (device, event_id) do update set n = rc_events_prog.n + (new.packs - old.packs);
    end loop;
  end if;
  return new;
end $function$

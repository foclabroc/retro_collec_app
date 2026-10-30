create or replace function public.rc__rn_solo_pay()
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare d record; r record; pl int; rw jsonb;
begin
  if not exists (select 1 from public.rc_rn_day where not paid and day < public.rc__today()) then return; end if;
  if not pg_try_advisory_xact_lock(hashtext('rc_rn_solo_pay')) then return; end if;
  for d in select day from public.rc_rn_day where not paid and day < public.rc__today() order by day for update loop
    pl := 0;
    for r in select b.device, b.score from public.rc_rn_best b join public.rc_players p on p.device = b.device
              where b.day = d.day and b.score > 0 and not coalesce(p.blocked, false)
              order by b.score desc, b.at asc limit 3 loop
      pl := pl + 1;
      rw := public.rc__rj_solo_prize(pl);
      insert into public.rc_rn_wins (day, place, device, score, reward) values (d.day, pl, r.device, r.score, rw)
      on conflict (day, place) do nothing;
      if found then
        perform public.rc__grant(r.device, rw);
        if pl = 1 then perform public.rc__feed_put(r.device, 'rnsolo', null, null, null, null, r.score, null); end if;
      end if;
    end loop;
    update public.rc_rn_day set paid = true where day = d.day;
  end loop;
end $function$;

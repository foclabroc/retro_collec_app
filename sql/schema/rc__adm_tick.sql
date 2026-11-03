create or replace function public.rc__adm_tick()
 returns void language plpgsql security definer set search_path to 'public' as $$
declare s public.rc_admin_sched; e text; nx timestamptz; step interval;
begin
  if not pg_try_advisory_xact_lock(hashtext('rc__adm_tick')) then return; end if;
  for s in select * from public.rc_admin_sched where done_at is null and at <= now() order by at limit 20 loop
    e := null;
    begin perform public.rc__adm_run(s);
    exception when others then e := sqlerrm; end;
    if s.every is null then
      update public.rc_admin_sched set done_at = now(), runs = runs + 1, last_err = e where id = s.id;
    else
      step := case s.every when 'day' then interval '1 day' else interval '7 days' end;
      nx := s.at; while nx <= now() loop nx := nx + step; end loop;
      update public.rc_admin_sched set runs = runs + 1, last_err = e, at = nx where id = s.id;
    end if;
  end loop;
  -- blocages arrivés à échéance
  with ex as (update public.rc_sanctions set lifted_at = until
               where kind = 'block' and lifted_at is null and until is not null and until <= now() returning device)
  update public.rc_players p set blocked = false
   where p.device in (select ex.device from ex)
     and not exists (select 1 from public.rc_sanctions z where z.device = p.device and z.kind = 'block' and z.lifted_at is null
                        and (z.until is null or z.until > now()));
end $$;

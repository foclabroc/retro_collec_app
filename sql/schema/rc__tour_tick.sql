create or replace function public.rc__tour_tick()
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare x bigint;
begin
  if not pg_try_advisory_xact_lock(7311001) then return; end if;
  for x in select id from public.rc_tour where status = 'open' and start_at <= now() loop
    perform public.rc__tour_start(x);
  end loop;
  for x in select id from public.rc_tour_matches where status = 'wait' and start_at + interval '3 minutes' < now() loop
    perform public.rc__tour_resolve(x);
  end loop;
  for x in select id from public.rc_c4 where tmatch is not null and status = 'playing' loop
    perform public.rc__c4_settle(x);
  end loop;
  for x in select id from public.rc_bs where tmatch is not null and status in ('setup', 'playing') loop
    perform public.rc__bs_settle(x);
  end loop;
end $function$;

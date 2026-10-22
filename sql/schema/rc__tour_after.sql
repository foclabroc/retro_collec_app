create or replace function public.rc__tour_after(p_tid bigint)
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare t public.rc_tour; w text[]; n int; i int;
begin
  select * into t from public.rc_tour where id = p_tid for update;
  if t.id is null or t.status <> 'running' then return; end if;
  if exists (select 1 from public.rc_tour_matches where tid = p_tid and round = t.round and status <> 'done') then return; end if;
  if t.round >= t.rounds then
    perform public.rc__tour_finish(p_tid);
    return;
  end if;
  select array_agg(winner order by slot) into w from public.rc_tour_matches where tid = p_tid and round = t.round;
  n := array_length(w, 1) / 2;
  for i in 0 .. n - 1 loop
    insert into public.rc_tour_matches (tid, round, slot, p1, p2, start_at, best)
    values (p_tid, t.round + 1, i, w[2 * i + 1], w[2 * i + 2], now(), case when t.round + 1 = t.rounds then 3 else 1 end)
    on conflict (tid, round, slot) do nothing;
  end loop;
  update public.rc_tour set round = round + 1 where id = p_tid;
end $function$;

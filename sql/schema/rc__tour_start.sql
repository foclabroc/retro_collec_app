create or replace function public.rc__tour_start(p_tid bigint)
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare t public.rc_tour; devs text[]; cnt int; n int := 2; r int := 0; m int; i int;
begin
  select * into t from public.rc_tour where id = p_tid for update;
  if t.id is null or t.status <> 'open' then return; end if;
  select array_agg(device order by random()) into devs from public.rc_tour_players where tid = p_tid;
  cnt := coalesce(array_length(devs, 1), 0);
  if cnt < 2 then
    perform public.rc__tour_cancel(p_tid);
    return;
  end if;
  while n < cnt loop n := n * 2; end loop;
  n := least(n, t.size);
  m := n;
  while m > 1 loop r := r + 1; m := m / 2; end loop;
  m := n / 2;
  for i in 0 .. m - 1 loop
    insert into public.rc_tour_matches (tid, round, slot, p1, p2, start_at, best)
    values (p_tid, 1, i, devs[i + 1], devs[m + i + 1], now(), case when r = 1 then 3 else 1 end)
    on conflict (tid, round, slot) do nothing;
  end loop;
  update public.rc_tour_matches set status = 'done', winner = p1, reason = 'bye'
   where tid = p_tid and round = 1 and p2 is null and status <> 'done';
  update public.rc_tour set status = 'running', round = 1, rounds = r,
         pot = (select coalesce(sum(paid), 0) from public.rc_tour_players where tid = p_tid)
   where id = p_tid;
  perform public.rc__tour_after(p_tid);
end $function$;

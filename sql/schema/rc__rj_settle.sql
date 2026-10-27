create or replace function public.rc__rj_settle(p_id bigint)
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare g public.rc_rj; over boolean; d1 boolean; d2 boolean; w int; why text;
begin
  select * into g from public.rc_rj where id = p_id for update;
  if g.id is null then return; end if;
  if g.status = 'invite' then
    if now() > g.created_at + interval '2 minutes' then
      update public.rc_rj set status = 'done', reason = 'expired', move_at = now() where id = p_id;
    end if;
    return;
  end if;
  if g.status <> 'playing' then return; end if;
  -- plus de nouvelles depuis 20 s (et la partie a commencé depuis 20 s) : compté tombé
  if g.dead1 is null and now() > g.start_at + interval '20 seconds'
     and coalesce(g.seen1, g.start_at) < now() - interval '20 seconds' then
    g.dead1 := coalesce(g.seen1, g.start_at); g.gone1 := true;
    update public.rc_rj set dead1 = g.dead1, gone1 = true where id = p_id;
  end if;
  if g.dead2 is null and now() > g.start_at + interval '20 seconds'
     and coalesce(g.seen2, g.start_at) < now() - interval '20 seconds' then
    g.dead2 := coalesce(g.seen2, g.start_at); g.gone2 := true;
    update public.rc_rj set dead2 = g.dead2, gone2 = true where id = p_id;
  end if;
  over := now() > g.end_at + interval '5 seconds';  -- 2 min passées (+ 5 s pour la dernière hauteur)
  d1 := g.dead1 is not null or over;
  d2 := g.dead2 is not null or over;
  if d1 and d2 then
    w := case when g.h1 > g.h2 then 1 when g.h2 > g.h1 then 2 else 0 end;
  elsif g.dead1 is not null and g.h2 > g.h1 then
    w := 2;
  elsif g.dead2 is not null and g.h1 > g.h2 then
    w := 1;
  else
    return;  -- on continue
  end if;
  why := case when w = 0 then 'draw'
              when (w = 1 and g.gone2) or (w = 2 and g.gone1) then 'timeout'
              else 'win' end;
  perform public.rc__rj_finish(p_id, w, why);
end $function$;

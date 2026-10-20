CREATE OR REPLACE FUNCTION public.rc__bs_settle(p_id bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare g public.rc_bs; lim interval; cell int; shots text; late int; guard int := 0;
begin
  select * into g from public.rc_bs where id = p_id for update;
  if g.id is null then return; end if;
  lim := public.rc__bs_limit(g.mode, g.status);
  if g.status = 'invite' and now() > g.created_at + lim then
    update public.rc_bs set status = 'done', reason = 'expired' where id = p_id;
  elsif g.status = 'setup' and now() > g.move_at + lim then
    update public.rc_bs set fleet1 = coalesce(fleet1, public.rc__bs_random()), fleet2 = coalesce(fleet2, public.rc__bs_random()),
                            status = 'playing', turn = 1, move_at = g.move_at + lim where id = p_id;
    perform public.rc__bs_settle(p_id);
  elsif g.status = 'playing' then
    lim := public.rc__bs_limit(g.mode, 'playing');
    while g.status = 'playing' and now() > g.move_at + lim and guard < 200 loop
      guard := guard + 1;
      late := case when g.turn = 1 then g.late1 else g.late2 end;
      if late >= 2 then
        perform public.rc__bs_finish(p_id, 3 - g.turn, 'timeout');
      else
        if g.turn = 1 then update public.rc_bs set late1 = late1 + 1 where id = p_id;
        else update public.rc_bs set late2 = late2 + 1 where id = p_id; end if;
        shots := case when g.turn = 1 then g.shots1 else g.shots2 end;
        select x into cell from generate_series(0, 63) x where substr(shots, x + 1, 1) = '0' order by random() limit 1;
        perform public.rc__bs_fire(p_id, g.turn, cell, g.move_at + lim);
      end if;
      select * into g from public.rc_bs where id = p_id;
    end loop;
  end if;
end $function$

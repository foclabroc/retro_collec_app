CREATE OR REPLACE FUNCTION public.rc__feed_duel()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare k text := case when tg_table_name = 'rc_bs' then 'bs' else 'c4' end;
begin
  if new.status <> 'done' or old.status = 'done' then return new; end if;
  if new.reason not in ('win', 'draw', 'timeout', 'resign') or new.moves = 0 then return new; end if;
  if new.winner = 0 then
    perform public.rc__feed_put(new.p1, k || 'draw', new.p2, null, null, null, null, new.reason);
  elsif new.winner in (1, 2) then
    perform public.rc__feed_put(case new.winner when 1 then new.p1 else new.p2 end, k,
                                case new.winner when 1 then new.p2 else new.p1 end,
                                null, null, null, case when new.stake > 0 then new.stake * 2 when new.paid then 150 end, new.reason);
  end if;
  return new;
end $function$

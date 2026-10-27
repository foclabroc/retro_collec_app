create or replace function public.rc__feed_duel()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare k text := case tg_table_name when 'rc_bs' then 'bs' when 'rc_rj' then 'rj' else 'c4' end;
begin
  if new.status <> 'done' or old.status = 'done' then return new; end if;
  if new.tmatch is not null then return new; end if;  -- tournoi : une seule nouvelle à la fin
  if new.reason not in ('win', 'draw', 'timeout', 'resign') or new.moves = 0 then return new; end if;
  if new.winner = 0 then
    perform public.rc__feed_put(new.p1, k || 'draw', new.p2, null, null, null, null, new.reason);
  elsif new.winner in (1, 2) then
    perform public.rc__feed_put(case new.winner when 1 then new.p1 else new.p2 end, k,
                                case new.winner when 1 then new.p2 else new.p1 end,
                                null, null, null, case when new.stake > 0 then new.stake * 2 when new.paid then 150 end, new.reason);
  end if;
  return new;
end $function$;

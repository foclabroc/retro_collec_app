create or replace function public.rc__act_duel()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare jeu text := case when tg_table_name = 'rc_bs' then 'Console Wars' else '4 en ligne' end;
        how text; ami text;
begin
  begin
    if tg_op = 'INSERT' then
      perform public.rc__act(new.p1, 'duel', 2, 'invite à ' || jeu, null, null, new.p2);
    elsif new.status = 'done' and old.status is distinct from 'done' then
      if new.reason in ('win', 'draw', 'timeout', 'resign') then
        how := case new.reason when 'timeout' then ' (temps écoulé)' when 'resign' then ' (abandon)' else '' end;
        ami := case when coalesce(new.paid, false) then '' else ' — amical' end;
        if new.winner in (1, 2) then
          perform public.rc__act(case new.winner when 1 then new.p1 else new.p2 end, 'duel', 2,
                                 'gagne à ' || jeu || how || ami || ' contre', null, null,
                                 case new.winner when 1 then new.p2 else new.p1 end);
          perform public.rc__act(case new.winner when 1 then new.p2 else new.p1 end, 'duel', 2,
                                 'perd à ' || jeu || how || ami || ' contre', null, null,
                                 case new.winner when 1 then new.p1 else new.p2 end);
        else
          perform public.rc__act(new.p1, 'duel', 2, 'match nul à ' || jeu || ami || ' contre', null, null, new.p2);
          perform public.rc__act(new.p2, 'duel', 2, 'match nul à ' || jeu || ami || ' contre', null, null, new.p1);
        end if;
      elsif new.reason = 'declined' then
        perform public.rc__act(new.p2, 'duel', 2, 'refuse le ' || jeu || ' de', null, null, new.p1);
      elsif new.reason = 'cancelled' then
        perform public.rc__act(new.p1, 'duel', 2, 'annule son invitation à ' || jeu || ' pour', null, null, new.p2);
      end if;
    end if;
  exception when others then null;
  end;
  return new;
end $function$;

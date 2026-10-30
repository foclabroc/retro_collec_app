create or replace function public.rc_rj_stats(p_device text, p_kind text default 'jump')
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to 'public'
as $function$
declare w int := 0; l int := 0; d int := 0; net int := 0; streak int := 0; best int := 0; r record; counting boolean := true;
begin
  for r in select (case when p1 = p_device then 1 else 2 end) as side, winner, paid,
                  case when p1 = p_device then h1 else h2 end as h
             from public.rc_rj
            where (p1 = p_device or p2 = p_device) and status = 'done' and winner is not null and kind = p_kind
            order by move_at desc loop
    best := greatest(best, r.h);
    if r.winner = 0 then d := d + 1; counting := false; if r.paid then net := net + 10; end if;
    elsif r.winner = r.side then w := w + 1; if r.paid then net := net + 150; end if; if counting then streak := streak + 1; end if;
    else l := l + 1; if r.paid then net := net + 10; end if; counting := false;
    end if;
  end loop;
  return jsonb_build_object('wins', w, 'losses', l, 'draws', d, 'streak', streak, 'net', net, 'best', best);
end $function$;

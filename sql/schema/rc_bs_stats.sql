CREATE OR REPLACE FUNCTION public.rc_bs_stats(p_device text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare w int := 0; l int := 0; net int := 0; streak int := 0; r record; counting boolean := true;
begin
  for r in select (case when p1 = p_device then 1 else 2 end) as side, winner, stake
             from public.rc_bs
            where (p1 = p_device or p2 = p_device) and status = 'done' and winner is not null
            order by move_at desc loop
    if r.winner = r.side then w := w + 1; net := net + r.stake; if counting then streak := streak + 1; end if;
    else l := l + 1; net := net - r.stake; counting := false;
    end if;
  end loop;
  return jsonb_build_object('wins', w, 'losses', l, 'draws', 0, 'streak', streak, 'net', net);
end $function$

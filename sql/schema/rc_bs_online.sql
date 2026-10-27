CREATE OR REPLACE FUNCTION public.rc_bs_online(p_device text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  update public.rc_players set seen_at = now() where device = p_device;
  return coalesce((
    select jsonb_agg(jsonb_build_object('pid', p.pid, 'name', p.name, 'avatar', p.avatar, 'score', p.score,
             'coins_ok', true, 'friendly', public.rc__duel_why(p_device, p.device),
             'busy', public.rc__duel_busy(p.device),
             'w', (select count(*) from public.rc_bs g where g.status = 'done'
                     and ((g.p1 = p.device and g.winner = 1) or (g.p2 = p.device and g.winner = 2))),
             'l', (select count(*) from public.rc_bs g where g.status = 'done'
                     and ((g.p1 = p.device and g.winner = 2) or (g.p2 = p.device and g.winner = 1))))
           order by p.seen_at desc)
      from (select * from public.rc_players q
             where q.device <> p_device and q.packs > 0 and q.seen_at > now() - interval '75 seconds'
             order by q.seen_at desc limit 50) p), '[]'::jsonb);
end $function$;

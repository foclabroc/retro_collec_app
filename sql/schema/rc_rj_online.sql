create or replace function public.rc_rj_online(p_device text, p_kind text default 'jump')
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
begin
  update public.rc_players set seen_at = now() where device = p_device;
  return coalesce((
    select jsonb_agg(jsonb_build_object('pid', p.pid, 'name', p.name, 'avatar', p.avatar, 'score', p.score,
             'coins_ok', true, 'friendly', public.rc__duel_why(p_device, p.device),
             'w', (select count(*) from public.rc_rj g where g.status = 'done' and g.kind = p_kind
                     and ((g.p1 = p.device and g.winner = 1) or (g.p2 = p.device and g.winner = 2))),
             'l', (select count(*) from public.rc_rj g where g.status = 'done' and g.kind = p_kind
                     and ((g.p1 = p.device and g.winner = 2) or (g.p2 = p.device and g.winner = 1))),
             'busy', public.rc__duel_busy(p.device))
           order by p.seen_at desc)
      from (select * from public.rc_players q
             where q.device <> p_device and q.packs > 0 and q.seen_at > now() - interval '75 seconds'
               and case when p_kind = 'run' then public.rc__rn_ok(q.device) else q.rj_ok end
             order by q.seen_at desc limit 50) p), '[]'::jsonb);
end $function$;

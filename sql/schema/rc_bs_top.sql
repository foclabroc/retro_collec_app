CREATE OR REPLACE FUNCTION public.rc_bs_top()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(jsonb_agg(x order by (x->>'wins')::int desc), '[]'::jsonb) from (
    select jsonb_build_object('pid', p.pid, 'name', p.name, 'avatar', p.avatar, 'wins', count(*),
                              'online', coalesce(p.seen_at > now() - interval '2 minutes', false)) as x
      from public.rc_bs g
      join public.rc_players p on p.device = case when g.winner = 1 then g.p1 else g.p2 end
     where g.status = 'done' and g.winner in (1, 2) and g.move_at > now() - interval '7 days'
     group by p.pid, p.name, p.avatar, p.seen_at
     order by count(*) desc limit 10) t $function$

create or replace function public.rc_rj_top(p_kind text default 'jump')
 returns jsonb
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select coalesce(jsonb_agg(x order by (x->>'wins')::int desc), '[]'::jsonb) from (
    select jsonb_build_object('pid', p.pid, 'name', p.name, 'avatar', p.avatar, 'wins', count(*),
                              'online', coalesce(p.seen_at > now() - interval '75 seconds', false)) as x
      from public.rc_rj g
      join public.rc_players p on p.device = case when g.winner = 1 then g.p1 else g.p2 end
     where g.status = 'done' and g.winner in (1, 2) and g.move_at > now() - interval '7 days' and g.kind = p_kind
     group by p.pid, p.name, p.avatar, p.seen_at
     order by count(*) desc limit 10) t $function$;

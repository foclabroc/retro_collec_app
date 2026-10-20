CREATE OR REPLACE FUNCTION public.rc_feed_list(p_after bigint DEFAULT 0)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(jsonb_agg(x order by (x->>'id')::bigint desc), '[]'::jsonb) from (
    select jsonb_build_object('id', f.id, 'at', f.at, 'kind', f.kind, 'card', f.card, 'f', f.finish,
                              'sys', f.sys, 'n', f.n, 'pid', p.pid, 'name', p.name, 'avatar', p.avatar) as x
      from public.rc_feed f join public.rc_players p on p.device = f.device
     where f.id > coalesce(p_after, 0) and f.kind in ('legend', 'gold', 'set', 'gamedle')
     order by f.id desc limit 60) s $function$

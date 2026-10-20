CREATE OR REPLACE FUNCTION public.rc_feed_list2(p_after bigint DEFAULT 0)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(jsonb_agg(x order by (x->>'id')::bigint desc), '[]'::jsonb) from (
    select jsonb_build_object('id', f.id, 'at', f.at, 'kind', f.kind, 'card', f.card, 'f', f.finish,
                              'sys', f.sys, 'n', f.n, 'x', f.extra,
                              'pid', p.pid, 'name', p.name, 'avatar', p.avatar,
                              'pid2', o.pid, 'name2', o.name, 'avatar2', o.avatar) as x
      from public.rc_feed f
      join public.rc_players p on p.device = f.device
      left join public.rc_players o on o.device = f.other
     where f.id > coalesce(p_after, 0)
     order by f.id desc limit 100) s $function$

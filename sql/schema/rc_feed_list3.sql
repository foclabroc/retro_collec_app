CREATE OR REPLACE FUNCTION public.rc_feed_list3(p_device text, p_after bigint DEFAULT 0)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(jsonb_agg(x order by (x->>'id')::bigint desc), '[]'::jsonb) from (
    select jsonb_build_object('id', f.id, 'at', f.at, 'kind', f.kind, 'card', f.card, 'f', f.finish,
                              'sys', f.sys, 'n', f.n, 'x', f.extra,
                              'pid', p.pid, 'name', p.name, 'avatar', p.avatar,
                              'pid2', o.pid, 'name2', o.name, 'avatar2', o.avatar,
                              'rx', (select jsonb_build_array(count(*) filter (where r.emo = 0), count(*) filter (where r.emo = 1),
                                                              count(*) filter (where r.emo = 2))
                                       from public.rc_feed_react r where r.feed_id = f.id),
                              'me', coalesce((select r.emo from public.rc_feed_react r where r.feed_id = f.id and r.device = p_device), -1)) as x
      from public.rc_feed f
      join public.rc_players p on p.device = f.device
      left join public.rc_players o on o.device = f.other
     where f.id > coalesce(p_after, 0)
     order by f.id desc limit 100) s $function$

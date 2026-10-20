CREATE OR REPLACE FUNCTION public.rc__poll_json(p rc_polls)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select jsonb_build_object('id', p.id, 'question', p.question, 'options', p.options, 'ends_at', p.ends_at,
                            'closed', p.closed or p.ends_at <= now(), 'created_at', p.created_at,
                            'votes', (select jsonb_agg((select count(*) from public.rc_poll_votes v where v.poll_id = p.id and v.choice = i) order by i)
                                        from generate_series(0, jsonb_array_length(p.options) - 1) i),
                            'total', (select count(*) from public.rc_poll_votes v where v.poll_id = p.id)) $function$

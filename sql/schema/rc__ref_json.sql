CREATE OR REPLACE FUNCTION public.rc__ref_json(p_dev text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select jsonb_build_object(
    'code', public.rc__ref_code(p.pid),
    'can_enter', p.referrer is null and p.created_at > now() - interval '7 days',
    'sponsor', (select jsonb_build_object('name', s.name, 'pid', s.pid, 'avatar', s.avatar) from public.rc_players s where s.device = p.referrer),
    'paid', p.ref_paid, 'packs', p.packs, 'days', p.days,
    'max', 10,
    'kids', coalesce((select jsonb_agg(jsonb_build_object('name', k.name, 'pid', k.pid, 'avatar', k.avatar,
                                                         'packs', k.packs, 'days', k.days, 'paid', k.ref_paid)
                                       order by k.created_at desc)
                        from public.rc_players k where k.referrer = p.device), '[]'::jsonb))
    from public.rc_players p where p.device = p_dev $function$

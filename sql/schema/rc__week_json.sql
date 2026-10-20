CREATE OR REPLACE FUNCTION public.rc__week_json(p_dev text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select jsonb_build_object(
    'kinds', to_jsonb(public.rc__wkinds()), 'goals', to_jsonb(public.rc__wgoals()), 'rewards', to_jsonb(public.rc__wrewards()),
    'prog', to_jsonb(p.w_prog), 'claim', p.w_claim,
    'chest', jsonb_build_object('coins', 500, 'pixels', 2, 'premium', 1),
    'ends', extract(epoch from ((public.rc__week() + 7)::timestamp at time zone 'Europe/Paris'))::bigint,
    'coins', p.coins, 'pixels', p.pixels,
    'gifts', (select count(*)::int from public.rc_gifts g where g.receiver = p_dev and g.opened_at is null))
    from public.rc_players p where p.device = p_dev $function$

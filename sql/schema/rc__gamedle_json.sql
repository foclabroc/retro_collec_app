CREATE OR REPLACE FUNCTION public.rc__gamedle_json(p_dev text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select jsonb_build_object(
    'day', (public.rc__today() - date '2026-10-15'),
    'card', public.rc__gamedle_card(public.rc__today()),
    'guesses', coalesce((select to_jsonb(g.guesses) from public.rc_gamedle g where g.device = p_dev and g.day = public.rc__today()), '[]'::jsonb),
    'won', coalesce((select g.won from public.rc_gamedle g where g.device = p_dev and g.day = public.rc__today()), false),
    'solvers', (select count(*) from public.rc_gamedle g where g.day = public.rc__today() and g.won),
    'players', (select count(*) from public.rc_gamedle g where g.day = public.rc__today()),
    'coins', (select coins from public.rc_players where device = p_dev)) $function$

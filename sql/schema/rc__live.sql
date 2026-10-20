create or replace function public.rc__live()
 returns jsonb
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select jsonb_build_object(
    'saga', public.rc__cfg('saga', 3.2), 'holo', public.rc__cfg('holo', 5), 'gold', public.rc__cfg('gold', 0.5),
    'fullart', public.rc__cfg('fullart', 0.2),
    'mixte', public.rc__cfg('mixte', 100), 'console', public.rc__cfg('console', 150),
    'premium', public.rc__cfg('premium', 400), 'mystery', public.rc__cfg('mystery', 120),
    'chest_coins', public.rc__cfg('chest_coins', 500), 'chest_pixels', public.rc__cfg('chest_pixels', 2),
    -- effets en cours (affichage) : réductions par paquet, multiplicateurs
    'promo', jsonb_build_object('mixte', public.rc__promo('mixte'), 'console', public.rc__promo('console'),
                                'premium', public.rc__promo('premium'), 'mystery', public.rc__promo('mystery'), 'lot', public.rc__promo('lot')),
    'holo_x', coalesce(public.rc__effect('holo_x'), 1), 'rare_x', coalesce(public.rc__effect('rare_x'), 1),
    'recycle_x', coalesce(public.rc__effect('recycle_x'), 1), 'duel_x', coalesce(public.rc__effect('duel_x'), 1)) $function$;

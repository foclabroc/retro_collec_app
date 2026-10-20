create or replace function public.rc__wpool()
 returns table(id integer, kind text, goal integer, reward integer)
 language sql
 immutable
as $function$
  -- réservoir des défis de la semaine : 6 sont tirés au hasard chaque lundi (ne pas renuméroter)
  values (1, 'open', 10, 150), (2, 'gift', 9, 100), (3, 'trade', 3, 200), (4, 'win', 2, 200),
         (5, 'gamedle', 3, 100), (6, 'epic', 1, 150), (7, 'play', 4, 150), (8, 'new', 15, 150),
         (9, 'quiz', 30, 100), (10, 'sale', 2, 150), (11, 'free', 5, 150), (12, 'premium', 2, 150) $function$;
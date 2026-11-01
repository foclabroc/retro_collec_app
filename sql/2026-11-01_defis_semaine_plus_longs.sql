-- Défis de la semaine plus longs : objectifs ~2,5x plus hauts, récompenses relevées. Relançable.
create or replace function public.rc__wpool()
 returns table(id integer, kind text, goal integer, reward integer)
 language sql
 immutable
as $function$
  -- réservoir des défis de la semaine : 6 sont tirés au hasard chaque lundi (ne pas renuméroter)
  values (1, 'open', 25, 250), (2, 'gift', 18, 200), (3, 'trade', 6, 300), (4, 'win', 5, 300),
         (5, 'gamedle', 6, 200), (6, 'epic', 3, 300), (7, 'play', 10, 250), (8, 'new', 40, 300),
         (9, 'quiz', 50, 200), (10, 'sale', 5, 250), (11, 'free', 7, 250), (12, 'premium', 5, 250) $function$;

alter function public.rc__wpool() owner to rc_owner;

notify pgrst, 'reload schema';

create or replace function public.rc__wpool()
 returns table(id integer, kind text, goal integer, reward integer)
 language sql stable security definer set search_path to 'public' as $$
  -- réservoir des défis de la semaine : 6 sont tirés chaque lundi (ne pas renuméroter) ; surcharges : rc_config « wpool »
  select d.id, d.kind, coalesce((o.e->>'goal')::int, d.goal), coalesce((o.e->>'reward')::int, d.reward)
    from (values (1, 'open', 25, 250), (2, 'gift', 18, 200), (3, 'trade', 6, 300), (4, 'win', 5, 300), (5, 'gamedle', 6, 200),
                 (6, 'epic', 3, 300), (7, 'play', 10, 250), (8, 'new', 40, 300), (9, 'quiz', 50, 200), (10, 'sale', 5, 250),
                 (11, 'free', 7, 250), (12, 'premium', 5, 250)) d(id, kind, goal, reward)
    left join lateral (select e from jsonb_array_elements(coalesce((select value from public.rc_config where key = 'wpool'), '[]'::jsonb)) e
                        where (e->>'id')::int = d.id limit 1) o on true
$$;

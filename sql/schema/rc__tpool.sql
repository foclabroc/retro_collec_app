create or replace function public.rc__tpool()
 returns table(kind text, t1 integer, t2 integer, t3 integer, ord integer)
 language sql
 immutable
as $function$
  -- trophees a 3 paliers (bronze, argent, or) ; textes et icones dans lib/trophies.dart
  values ('packs', 25, 100, 500, 1), ('cards', 100, 400, 1000, 2), ('consoles', 1, 5, 29, 3),
         ('legend', 1, 10, 50, 4), ('fullart', 1, 10, 30, 5), ('fuse', 5, 25, 100, 6),
         ('wins', 10, 50, 200, 7), ('gifts', 10, 50, 200, 8), ('sales', 5, 25, 100, 9),
         ('trades', 5, 25, 100, 10), ('gamedle', 10, 50, 200, 11), ('chest', 1, 5, 20, 12),
         ('sagas', 1, 5, 19, 13), ('days', 7, 30, 100, 14), ('epics', 10, 50, 200, 15), ('holo', 10, 50, 200, 16),
         ('gold', 5, 25, 100, 17), ('recycle', 50, 250, 1000, 18), ('quiz', 50, 250, 1000, 19), ('played', 20, 100, 400, 20),
         ('defis', 10, 50, 200, 21), ('premium', 5, 25, 100, 22), ('buys', 5, 25, 100, 23), ('firsttry', 1, 5, 20, 24),
         ('tourney', 1, 3, 10, 25), ('pioche', 5, 30, 100, 26), ('express', 5, 30, 100, 27),
         ('wheel', 10, 50, 200, 28), ('pokemon', 10, 50, 185, 29),
         ('react', 10, 50, 200, 30), ('craft', 5, 25, 100, 31), ('sagacards', 25, 100, 250, 32),
         -- ajoutes le 7/11
         ('cartoon', 10, 40, 80, 33), ('dragonball', 50, 200, 556, 34), ('dbholo', 10, 50, 146, 35),
         ('sunday', 1, 4, 12, 36), ('podium', 1, 5, 20, 37), ('score', 1000, 5000, 15000, 38),
         ('boosters', 5, 25, 100, 39),
         -- ajoute le 24/11
         ('platine', 1, 5, 15, 40) $function$;

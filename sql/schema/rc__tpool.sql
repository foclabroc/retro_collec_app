create or replace function public.rc__tpool()
 returns table(kind text, t1 integer, t2 integer, t3 integer, ord integer)
 language sql
 immutable
as $function$
  -- trophées à 3 paliers (bronze, argent, or) ; textes et icônes dans lib/trophies.dart
  values ('packs', 25, 100, 500, 1), ('cards', 100, 400, 1000, 2), ('consoles', 1, 5, 14, 3),
         ('legend', 1, 10, 50, 4), ('fullart', 1, 10, 30, 5), ('fuse', 5, 25, 100, 6),
         ('wins', 10, 50, 200, 7), ('gifts', 10, 50, 200, 8), ('sales', 5, 25, 100, 9),
         ('trades', 5, 25, 100, 10), ('gamedle', 10, 50, 200, 11), ('chest', 1, 5, 20, 12) $function$;

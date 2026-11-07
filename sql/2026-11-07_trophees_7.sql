-- 7 nouveaux trophees (39 au total)   (relancable)
--   cartoon : cartes Dessins animes differentes · dragonball : cartes Dragon Ball differentes · dbholo : holos Dragon Ball
--   sunday : cadeaux du dimanche recuperes (compteur, branche dans rc_sunday_claim) · podium : podiums des solos du jour
--   (Retro Jump + Course de jaquettes) · score : score de collection · boosters : boosters de serie achetes
-- A lancer APRES 2026-11-07_cadeau_dimanche.sql. Textes et icones : lib/trophies.dart.
create or replace function public.rc__tpool()
 returns table(kind text, t1 integer, t2 integer, t3 integer, ord integer)
 language sql
 immutable
as $function$
  -- trophées à 3 paliers (bronze, argent, or) ; textes et icônes dans lib/trophies.dart
  values ('packs', 25, 100, 500, 1), ('cards', 100, 400, 1000, 2), ('consoles', 1, 5, 29, 3),
         ('legend', 1, 10, 50, 4), ('fullart', 1, 10, 30, 5), ('fuse', 5, 25, 100, 6),
         ('wins', 10, 50, 200, 7), ('gifts', 10, 50, 200, 8), ('sales', 5, 25, 100, 9),
         ('trades', 5, 25, 100, 10), ('gamedle', 10, 50, 200, 11), ('chest', 1, 5, 20, 12),
         ('sagas', 1, 3, 12, 13), ('days', 7, 30, 100, 14), ('epics', 10, 50, 200, 15), ('holo', 10, 50, 200, 16),
         ('gold', 5, 25, 100, 17), ('recycle', 50, 250, 1000, 18), ('quiz', 50, 250, 1000, 19), ('played', 20, 100, 400, 20),
         ('defis', 10, 50, 200, 21), ('premium', 5, 25, 100, 22), ('buys', 5, 25, 100, 23), ('firsttry', 1, 5, 20, 24),
         ('tourney', 1, 3, 10, 25), ('pioche', 5, 30, 100, 26), ('express', 5, 30, 100, 27),
         ('wheel', 10, 50, 200, 28), ('pokemon', 10, 50, 185, 29),
         ('react', 10, 50, 200, 30), ('craft', 5, 25, 100, 31), ('sagacards', 25, 75, 156, 32),
         -- ajoutés le 7/11
         ('cartoon', 10, 40, 80, 33), ('dragonball', 25, 100, 200, 34), ('dbholo', 5, 20, 44, 35),
         ('sunday', 1, 4, 12, 36), ('podium', 1, 5, 20, 37), ('score', 1000, 5000, 15000, 38),
         ('boosters', 5, 25, 100, 39) $function$;
alter function public.rc__tpool() owner to rc_owner;

CREATE OR REPLACE FUNCTION public.rc__tn(p_dev text)
 RETURNS TABLE(kind text, n integer, got integer, t integer[], ord integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- progression de chaque trophée : paquets, cartes et consoles lus en direct, le reste compté
  select k.kind,
         case k.kind when 'packs' then p.packs
                     when 'cards' then p.cards
                     when 'consoles' then (select count(*)::int from public.rc_milestones m
                                            where m.device = p_dev and m.step = 100 and m.sys not like 'sg\_%')
                     when 'sagas' then (select count(*)::int from public.rc_milestones m
                                         where m.device = p_dev and m.step = 100 and m.sys like 'sg\_%')
                     when 'days' then p.days
                     when 'react' then (select count(*)::int from public.rc_feed_react r where r.device = p_dev)
                     when 'sagacards' then (select count(*)::int from public.rc_owned o join public.rc_cards cc on cc.id = o.card
                                             where o.device = p_dev and o.qty > 0 and cc.saga is not null and cc.saga not in ('pk', 'da', 'db'))
                     when 'pokemon' then (select count(*)::int from public.rc_owned o join public.rc_cards cc on cc.id = o.card
                                           where o.device = p_dev and o.qty > 0 and cc.saga = 'pk')
                     when 'cartoon' then (select count(distinct o.card)::int from public.rc_owned o join public.rc_cards cc on cc.id = o.card
                                           where o.device = p_dev and o.qty > 0 and cc.saga = 'da')
                     when 'dragonball' then (select count(distinct o.card)::int from public.rc_owned o join public.rc_cards cc on cc.id = o.card
                                              where o.device = p_dev and o.qty > 0 and cc.saga = 'db')
                     when 'dbholo' then (select count(distinct o.card)::int from public.rc_owned o join public.rc_cards cc on cc.id = o.card
                                          where o.device = p_dev and o.qty > 0 and cc.saga = 'db' and cc.rarity >= 4)
                     when 'podium' then (select count(*)::int from public.rc_rj_wins w where w.device = p_dev)
                                      + (select count(*)::int from public.rc_rn_wins w where w.device = p_dev)
                     when 'score' then p.score
                     when 'boosters' then (select count(*)::int from public.rc_pack_log l
                                            where l.device = p_dev and l.kind in ('pokemon', 'cartoon', 'dragonball'))
                     else coalesce(c.n, 0) end,
         coalesce(g.tier, 0), array[k.t1, k.t2, k.t3], k.ord
    from public.rc__tpool() k
    join public.rc_players p on p.device = p_dev
    left join public.rc_trophy_n c on c.device = p_dev and c.kind = k.kind
    left join public.rc_trophy_got g on g.device = p_dev and g.kind = k.kind $function$;
alter function public.rc__tn(text) owner to rc_owner;

-- trophee « sunday » : compte chaque cadeau du dimanche recupere
do $$
declare d text; a text; b text;
begin
  d := pg_get_functiondef('public.rc_sunday_claim(text,text)'::regprocedure);
  a := $x$  perform set_config('rc.gift_from', '', true);$x$;
  b := $x$  perform set_config('rc.gift_from', '', true);
  perform public.rc__tbump(p_device, 'sunday', 1);$x$;
  if position(b in d) > 0 then return; end if;
  if position(a in d) = 0 then raise exception 'texte introuvable dans rc_sunday_claim'; end if;
  execute replace(d, a, b);
end $$;

notify pgrst, 'reload schema';

select count(*) as trophees from public.rc__tpool();  -- 39

create or replace function public.rc__tn(p_dev text)
 returns table(kind text, n integer, got integer, t integer[], ord integer)
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  -- progression de chaque trophée : paquets, cartes et consoles lus en direct, le reste compté
  select k.kind,
         case k.kind when 'packs' then p.packs
                     when 'cards' then p.cards
                     when 'consoles' then (select count(*)::int from public.rc_milestones m
                                            where m.device = p_dev and m.step = 100 and m.sys not like 'sg\_%')
                     else coalesce(c.n, 0) end,
         coalesce(g.tier, 0), array[k.t1, k.t2, k.t3], k.ord
    from public.rc__tpool() k
    join public.rc_players p on p.device = p_dev
    left join public.rc_trophy_n c on c.device = p_dev and c.kind = k.kind
    left join public.rc_trophy_got g on g.device = p_dev and g.kind = k.kind $function$;

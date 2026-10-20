create or replace function public.rc__tshow(p_dev text)
 returns text
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  -- vitrine de trophées « type:palier » (3 cases, vides possibles), ex. « wins:3,,cards:2 »
  select coalesce(string_agg(case when g.tier > 0 then x.k || ':' || g.tier else '' end, ',' order by x.o), '')
    from public.rc_players p,
         unnest(string_to_array(nullif(p.trophies, ''), ',')) with ordinality x(k, o)
    left join public.rc_trophy_got g on g.device = p_dev and g.kind = x.k
   where p.device = p_dev $function$;

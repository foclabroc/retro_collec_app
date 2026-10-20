create or replace function public.rc__tshow_k(p_dev text)
 returns text[]
 language plpgsql
 stable security definer
 set search_path to 'public'
as $function$
-- les 3 trophées affichés : ceux choisis (débloqués), et les cases vides remplies par les meilleurs paliers
declare a text[]; r text[] := array['', '', '']; i int; k text;
begin
  select string_to_array(coalesce(trophies, ''), ',') into a from public.rc_players where device = p_dev;
  for i in 1..3 loop
    if i <= coalesce(array_length(a, 1), 0) and a[i] <> '' and not (a[i] = any(r))
       and exists (select 1 from public.rc_trophy_got g where g.device = p_dev and g.kind = a[i] and g.tier > 0) then
      r[i] := a[i];
    end if;
  end loop;
  for k in select g.kind from public.rc_trophy_got g join public.rc__tpool() p on p.kind = g.kind
            where g.device = p_dev and g.tier > 0 and not (g.kind = any(r)) order by g.tier desc, p.ord loop
    i := array_position(r, '');
    exit when i is null;
    r[i] := k;
  end loop;
  return r;
end $function$;

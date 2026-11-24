create or replace function public.rc__platine_mark(p_dev text, p_packs jsonb)
 returns jsonb
 language plpgsql
 set search_path to 'public'
as $function$
declare unl text[]; out jsonb := '[]'::jsonb; pk jsonb; e jsonb; one jsonb;
begin
  select array_agg(m.sys) into unl from public.rc_milestones m where m.device = p_dev and m.step = 100;
  if unl is null then return p_packs; end if;
  for pk in select * from jsonb_array_elements(p_packs) loop
    one := '[]'::jsonb;
    for e in select * from jsonb_array_elements(pk) loop
      if coalesce((e->>'f')::int, 0) < 3 and random() < 0.10
         and exists (select 1 from public.rc_cards c where c.id = e->>'c' and c.saga is null and c.sys = any(unl)) then
        e := jsonb_set(e, '{f}', '4'::jsonb);
      end if;
      one := one || jsonb_build_array(e);
    end loop;
    out := out || jsonb_build_array(one);
  end loop;
  return out;
end $function$;

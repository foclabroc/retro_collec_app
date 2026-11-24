create or replace function public.rc__platine_ok(p_dev text, p_card text)
 returns boolean
 language sql
 stable
 set search_path to 'public'
as $function$
  select exists (select 1 from public.rc_cards c join public.rc_milestones m on m.sys = c.sys
                  where c.id = p_card and c.saga is null and m.device = p_dev and m.step = 100) $function$;

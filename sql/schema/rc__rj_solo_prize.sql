create or replace function public.rc__rj_solo_prize(p_place integer)
 returns jsonb
 language sql
 immutable
as $function$
  select case p_place when 1 then '{"coins":300,"pixels":2}'::jsonb
                      when 2 then '{"coins":200,"pixels":1}'::jsonb
                      when 3 then '{"coins":100}'::jsonb end $function$;

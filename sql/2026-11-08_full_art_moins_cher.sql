-- Fabrication des full art moins chere : 1 500 fragments (epique) / 4 000 (legendaire), au lieu de 3 000 / 10 000   (relancable)
create or replace function public.rc__fragment_cost(r integer)
 returns integer
 language sql
 immutable
as $function$
  select case r when 3 then 1500 when 4 then 4000 else null end $function$;
alter function public.rc__fragment_cost(integer) owner to rc_owner;

notify pgrst, 'reload schema';

select public.rc__fragment_cost(3) as epique, public.rc__fragment_cost(4) as legendaire;  -- 1500 / 4000

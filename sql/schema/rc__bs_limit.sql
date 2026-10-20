CREATE OR REPLACE FUNCTION public.rc__bs_limit(p_mode text, p_status text)
 RETURNS interval
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select case when p_mode = 'turn' then interval '24 hours'
              when p_status = 'invite' then interval '2 minutes'
              when p_status = 'setup' then interval '2 minutes'
              else interval '30 seconds' end $function$

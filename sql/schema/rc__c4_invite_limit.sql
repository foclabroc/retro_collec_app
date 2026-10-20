CREATE OR REPLACE FUNCTION public.rc__c4_invite_limit(p_mode text)
 RETURNS interval
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select case when p_mode = 'live' then interval '2 minutes' else interval '24 hours' end $function$

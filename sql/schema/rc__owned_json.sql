CREATE OR REPLACE FUNCTION public.rc__owned_json(p_dev text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
  select coalesce(jsonb_agg(jsonb_build_array(card, finish, qty) order by card, finish), '[]'::jsonb)
    from public.rc_owned where device = p_dev $function$

CREATE OR REPLACE FUNCTION public.rc__bs_out(p_id bigint, p_device text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select public.rc__bs_json(g, p_device) || jsonb_build_object('coins', (select coins from public.rc_players where device = p_device))
    from public.rc_bs g where g.id = p_id $function$

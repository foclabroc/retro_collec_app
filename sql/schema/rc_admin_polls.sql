CREATE OR REPLACE FUNCTION public.rc_admin_polls(p_device text, p_sig text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  perform public.rc__admin(p_device, p_sig, 'polls');
  return coalesce((select jsonb_agg(public.rc__poll_json(p) order by p.id desc)
                     from (select * from public.rc_polls order by id desc limit 10) p), '[]'::jsonb);
end $function$

create or replace function public.rc_admin_log_list(p_device text, p_sig text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
begin
  perform public.rc__admin(p_device, p_sig, 'log');
  return coalesce((select jsonb_agg(jsonb_build_object('id', l.id, 'action', l.action, 'at', l.at,
                                                       'by', (select p.name from public.rc_players p where p.device = l.device)) order by l.id desc)
                     from (select * from public.rc_admin_log order by id desc limit 200) l), '[]'::jsonb);
end $function$;

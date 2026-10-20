CREATE OR REPLACE FUNCTION public.rc_admin_chat(p_device text, p_sig text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  perform public.rc__admin(p_device, p_sig, 'chat');
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', c.id, 'msg', c.msg, 'reports', c.reports, 'hidden', c.hidden, 'at', c.created_at,
                                        'name', p.name, 'pid', p.pid, 'avatar', p.avatar,
                                        'banned', exists (select 1 from public.rc_chat_bans b where b.device = c.device and (b.until is null or b.until > now())))
                     order by c.reports desc, c.id desc)
      from public.rc_chat c join public.rc_players p on p.device = c.device
     where (c.reports > 0 or c.hidden) and c.created_at > now() - interval '14 days'), '[]'::jsonb);
end $function$

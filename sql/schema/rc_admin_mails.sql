create or replace function public.rc_admin_mails(p_device text, p_sig text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
begin
  perform public.rc__admin(p_device, p_sig, 'mails');
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', m.id, 'title', m.title, 'body', m.body, 'coins', m.coins, 'pixels', m.pixels,
                                        'packs', m.packs, 'reward', m.reward, 'grp', m.grp, 'at', m.created_at,
                                        'to', case when m.device is null then null else (select p.name from public.rc_players p where p.device = m.device) end,
                                        'sent', case when m.grp is null then null else (select count(*) from public.rc_mail_to t where t.mail_id = m.id) end,
                                        'read', (select count(*) from public.rc_mail_got g where g.mail_id = m.id)) order by m.id desc)
      from (select * from public.rc_mail order by id desc limit 30) m), '[]'::jsonb);
end $function$;

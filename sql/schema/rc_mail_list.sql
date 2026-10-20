create or replace function public.rc_mail_list(p_device text, p_sig text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare v public.rc_players;
begin
  perform public.rc__check(p_sig, p_device || '|mail');
  select * into v from public.rc_players where device = p_device;
  if v.device is null then return '[]'::jsonb; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', m.id, 'title', m.title, 'body', m.body, 'coins', m.coins, 'pixels', m.pixels,
                                        'packs', m.packs, 'reward', m.reward, 'all', m.device is null, 'at', m.created_at) order by m.id)
      from public.rc_mail m
     where (m.device = p_device
            or (m.device is null and m.grp is null and m.created_at > v.created_at and m.created_at > now() - interval '30 days')
            or (m.grp is not null and m.created_at > now() - interval '30 days'
                and exists (select 1 from public.rc_mail_to t where t.mail_id = m.id and t.device = p_device)))
       and not exists (select 1 from public.rc_mail_got g where g.device = p_device and g.mail_id = m.id)), '[]'::jsonb);
end $function$;

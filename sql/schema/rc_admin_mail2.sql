create or replace function public.rc_admin_mail2(p_device text, p_sig text, p_target text, p_title text, p_body text, p_reward text)
 returns bigint
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare d text; v_id bigint; rw jsonb; t text := coalesce(p_target, 'all');
begin
  perform public.rc__admin(p_device, p_sig, 'mail2|' || t || '|' || coalesce(p_title, '') || '|' || coalesce(p_reward, ''));
  if trim(coalesce(p_title, '')) = '' then raise exception 'titre vide'; end if;
  rw := public.rc__rw_clean(coalesce(nullif(p_reward, ''), '{}')::jsonb);
  if t like 'pid:%' then
    select device into d from public.rc_players where pid = substr(t, 5);
    if d is null then raise exception 'joueur inconnu'; end if;
  elsif t not in ('all', 'active7', 'new7', 'inactive7') then
    raise exception 'groupe inconnu';
  end if;
  insert into public.rc_mail (device, title, body, coins, pixels, packs, reward, grp)
  values (d, left(trim(p_title), 80), left(coalesce(p_body, ''), 600), 0, 0, 0, rw, case when t in ('active7', 'new7', 'inactive7') then t end)
  returning rc_mail.id into v_id;
  if t in ('active7', 'new7', 'inactive7') then
    insert into public.rc_mail_to (mail_id, device)
    select v_id, p.device from public.rc_players p
     where (t = 'active7' and p.seen_at > now() - interval '7 days')
        or (t = 'new7' and p.created_at > now() - interval '7 days')
        or (t = 'inactive7' and (p.seen_at is null or p.seen_at <= now() - interval '7 days'));
  end if;
  return v_id;
end $function$;

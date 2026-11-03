create or replace function public.rc__adm_run(s public.rc_admin_sched)
 returns void language plpgsql security definer set search_path to 'public' as $$
declare a jsonb := s.args; t text; d text; v_id bigint; rw jsonb;
begin
  case s.op
  when 'mail' then
    t := coalesce(a->>'target', 'all'); rw := public.rc__rw_clean(coalesce(a->'reward', '{}'::jsonb));
    if t like 'pid:%' then select device into d from public.rc_players where pid = substr(t, 5); if d is null then raise exception 'joueur inconnu'; end if; end if;
    insert into public.rc_mail (device, title, body, coins, pixels, packs, reward, grp)
    values (d, left(coalesce(a->>'title', ''), 80), left(coalesce(a->>'body', ''), 600), 0, 0, 0, rw,
            case when t in ('active7', 'new7', 'inactive7') then t end) returning id into v_id;
    if t in ('active7', 'new7', 'inactive7') then
      insert into public.rc_mail_to (mail_id, device)
      select v_id, p.device from public.rc_players p
       where (t = 'active7' and p.seen_at > now() - interval '7 days') or (t = 'new7' and p.created_at > now() - interval '7 days')
          or (t = 'inactive7' and (p.seen_at is null or p.seen_at <= now() - interval '7 days'));
    end if;
  when 'banner' then
    insert into public.rc_config (key, value) values ('banner', jsonb_build_object('text', left(coalesce(a->>'text', ''), 200), 'until', a->>'until'))
    on conflict (key) do update set value = excluded.value;
  when 'live' then
    update public.rc_config set value = value || (a->'values') where key = 'live';
  when 'maint' then
    insert into public.rc_config (key, value) values ('maintenance', jsonb_build_object('on', coalesce((a->>'on')::boolean, false), 'msg', left(coalesce(a->>'msg', ''), 300)))
    on conflict (key) do update set value = excluded.value;
  when 'chat' then
    insert into public.rc_chat (device, msg) values (s.by_dev, left(coalesce(a->>'msg', ''), 300));
  when 'event' then
    update public.rc_events set active = coalesce((a->>'on')::boolean, true) where id = (a->>'id')::bigint;
  end case;
end $$;

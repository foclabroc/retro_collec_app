-- Actu : deux réactions de plus, 🙏 Merci (3) et 🎉 Bravo (4). Relançable.
-- (retire une éventuelle contrainte qui limiterait emo à 0-2)
do $$
declare c record;
begin
  for c in select conname from pg_constraint
            where conrelid = 'public.rc_feed_react'::regclass and contype = 'c' and pg_get_constraintdef(oid) ilike '%emo%' loop
    execute format('alter table public.rc_feed_react drop constraint %I', c.conname);
  end loop;
end $$;

create or replace FUNCTION public.rc_feed_react(p_device text, p_id bigint, p_emo integer, p_sig text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare cur int;
begin
  perform public.rc__check(p_sig, p_device || '|react|' || p_id || '|' || p_emo);
  if not exists (select 1 from public.rc_players where device = p_device) then raise exception 'joueur inconnu'; end if;
  if not exists (select 1 from public.rc_feed where id = p_id) then raise exception 'nouvelle introuvable'; end if;
  select emo into cur from public.rc_feed_react where feed_id = p_id and device = p_device;
  if p_emo is null or p_emo not between 0 and 4 or cur = p_emo then
    delete from public.rc_feed_react where feed_id = p_id and device = p_device;
  else
    insert into public.rc_feed_react (feed_id, device, emo) values (p_id, p_device, p_emo)
    on conflict (feed_id, device) do update set emo = excluded.emo, at = now();
  end if;
  return jsonb_build_object(
    'rx', (select jsonb_build_array(count(*) filter (where emo = 0), count(*) filter (where emo = 1), count(*) filter (where emo = 2),
                                    count(*) filter (where emo = 3), count(*) filter (where emo = 4))
             from public.rc_feed_react where feed_id = p_id),
    'me', coalesce((select emo from public.rc_feed_react where feed_id = p_id and device = p_device), -1));
end $function$;

create or replace FUNCTION public.rc_feed_list3(p_device text, p_after bigint DEFAULT 0)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(jsonb_agg(x order by (x->>'id')::bigint desc), '[]'::jsonb) from (
    select jsonb_build_object('id', f.id, 'at', f.at, 'kind', f.kind, 'card', f.card, 'f', f.finish,
                              'sys', f.sys, 'n', f.n, 'x', f.extra,
                              'pid', p.pid, 'name', p.name, 'avatar', p.avatar,
                              'pid2', o.pid, 'name2', o.name, 'avatar2', o.avatar,
                              'rx', (select jsonb_build_array(count(*) filter (where r.emo = 0), count(*) filter (where r.emo = 1),
                                                              count(*) filter (where r.emo = 2), count(*) filter (where r.emo = 3),
                                                              count(*) filter (where r.emo = 4))
                                       from public.rc_feed_react r where r.feed_id = f.id),
                              'me', coalesce((select r.emo from public.rc_feed_react r where r.feed_id = f.id and r.device = p_device), -1)) as x
      from public.rc_feed f
      join public.rc_players p on p.device = f.device
      left join public.rc_players o on o.device = f.other
     where f.id > coalesce(p_after, 0)
     order by f.id desc limit 100) s $function$;

alter function public.rc_feed_react(text, bigint, integer, text) owner to rc_owner;
alter function public.rc_feed_list3(text, bigint) owner to rc_owner;

notify pgrst, 'reload schema';

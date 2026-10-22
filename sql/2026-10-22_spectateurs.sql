-- 22/10/2026 : spectateurs visibles + réactions en direct pendant un duel en direct (4 en ligne / Console Wars).
-- Le spectateur se signale toutes les 20 s (rc_watch_join), part avec rc_watch_leave ; liste = vus il y a moins de 50 s.
-- Événements temps réel (canal de la partie + canaux des 2 joueurs) : 'watchers' {game, gid, list} et
-- 'wreact' {game, gid, pid, name, avatar, e}. Relançable.

create table if not exists public.rc_watch (
  game     text        not null,
  gid      bigint      not null,
  device   text        not null,
  seen_at  timestamptz not null default now(),
  react_at timestamptz,
  primary key (game, gid, device)
);
alter table public.rc_watch owner to rc_owner;
revoke all on public.rc_watch from public;

-- appareils des 2 joueurs d'une partie en direct encore en cours (null si finie / pas en direct)
create or replace function public.rc__watch_game(p_game text, p_id bigint)
 returns table(p1 text, p2 text)
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select g.p1, g.p2 from public.rc_c4 g
   where p_game = 'c4' and g.id = p_id and g.mode = 'live' and g.status = 'playing'
  union all
  select g.p1, g.p2 from public.rc_bs g
   where p_game = 'bs' and g.id = p_id and g.mode = 'live' and g.status in ('setup', 'playing') $function$;
alter function public.rc__watch_game(text, bigint) owner to rc_owner;

-- spectateurs actuels : [{pid, name, avatar}]
create or replace function public.rc__watch_list(p_game text, p_id bigint)
 returns jsonb
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select coalesce(jsonb_agg(jsonb_build_object('pid', p.pid, 'name', p.name, 'avatar', p.avatar) order by w.seen_at), '[]'::jsonb)
    from public.rc_watch w join public.rc_players p on p.device = w.device
   where w.game = p_game and w.gid = p_id and w.seen_at > now() - interval '50 seconds' $function$;
alter function public.rc__watch_list(text, bigint) owner to rc_owner;

-- envoi d'un événement aux spectateurs (canal de la partie) et aux 2 joueurs
create or replace function public.rc__watch_send(p_game text, p_id bigint, p_event text, p_payload jsonb)
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare r record;
begin
  perform public.rc__rt_safe(public.rc__rt_watch_topic(p_game, p_id), p_event, p_payload);
  for r in select * from public.rc__watch_game(p_game, p_id) loop
    if r.p1 is not null then perform public.rc__rt_safe(public.rc__rt_topic(r.p1), p_event, p_payload); end if;
    if r.p2 is not null then perform public.rc__rt_safe(public.rc__rt_topic(r.p2), p_event, p_payload); end if;
  end loop;
end $function$;
alter function public.rc__watch_send(text, bigint, text, jsonb) owner to rc_owner;

-- le spectateur arrive / reste (toutes les 20 s) → liste des spectateurs
create or replace function public.rc_watch_join(p_device text, p_game text, p_id bigint, p_sig text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare isnew boolean;
begin
  perform public.rc__check(p_sig, p_device || '|wjoin|' || p_game || '|' || p_id);
  if not exists (select 1 from public.rc__watch_game(p_game, p_id)) then
    return jsonb_build_object('list', '[]'::jsonb, 'over', true);
  end if;
  -- un joueur de la partie ne compte pas comme spectateur
  if exists (select 1 from public.rc__watch_game(p_game, p_id) x where p_device in (x.p1, x.p2)) then
    return jsonb_build_object('list', public.rc__watch_list(p_game, p_id));
  end if;
  select not exists (select 1 from public.rc_watch w where w.game = p_game and w.gid = p_id and w.device = p_device
                        and w.seen_at > now() - interval '50 seconds') into isnew;
  insert into public.rc_watch (game, gid, device) values (p_game, p_id, p_device)
  on conflict (game, gid, device) do update set seen_at = now();
  if isnew then
    perform public.rc__watch_send(p_game, p_id, 'watchers',
      jsonb_build_object('game', p_game, 'gid', p_id, 'list', public.rc__watch_list(p_game, p_id)));
  end if;
  -- ménage : spectateurs de parties finies depuis longtemps
  if random() < 0.05 then delete from public.rc_watch where seen_at < now() - interval '1 day'; end if;
  return jsonb_build_object('list', public.rc__watch_list(p_game, p_id));
end $function$;
alter function public.rc_watch_join(text, text, bigint, text) owner to rc_owner;

-- le spectateur part
create or replace function public.rc_watch_leave(p_device text, p_game text, p_id bigint, p_sig text)
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
begin
  perform public.rc__check(p_sig, p_device || '|wleave|' || p_game || '|' || p_id);
  delete from public.rc_watch where game = p_game and gid = p_id and device = p_device;
  if found then
    perform public.rc__watch_send(p_game, p_id, 'watchers',
      jsonb_build_object('game', p_game, 'gid', p_id, 'list', public.rc__watch_list(p_game, p_id)));
  end if;
end $function$;
alter function public.rc_watch_leave(text, text, bigint, text) owner to rc_owner;

-- liste des spectateurs (pour les joueurs, sans signature : rien de secret)
create or replace function public.rc_watchers(p_game text, p_id bigint)
 returns jsonb
 language sql
 stable security definer
 set search_path to 'public'
as $function$ select public.rc__watch_list(p_game, p_id) $function$;
alter function public.rc_watchers(text, bigint) owner to rc_owner;

-- réaction d'un spectateur (une toutes les 1,5 s au plus, emojis de la liste seulement)
create or replace function public.rc_watch_react(p_device text, p_game text, p_id bigint, p_e text, p_sig text)
 returns boolean
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v record;
begin
  perform public.rc__check(p_sig, p_device || '|wreact|' || p_game || '|' || p_id || '|' || p_e);
  if p_e not in ('👏', '🔥', '😂', '😮', '😱', '👍', '💀', '🎉', '😭', '🤯') then return false; end if;
  update public.rc_watch set react_at = now(), seen_at = now()
   where game = p_game and gid = p_id and device = p_device
     and (react_at is null or react_at < now() - interval '1.5 seconds');
  if not found then return false; end if;
  select pid, name, avatar into v from public.rc_players where device = p_device;
  perform public.rc__watch_send(p_game, p_id, 'wreact',
    jsonb_build_object('game', p_game, 'gid', p_id, 'pid', v.pid, 'name', v.name, 'avatar', v.avatar, 'e', p_e));
  return true;
end $function$;
alter function public.rc_watch_react(text, text, bigint, text, text) owner to rc_owner;

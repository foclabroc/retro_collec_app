-- Échanges : les cartes proposées sortent du stock tant que l'échange est en attente
-- (rendues si annulé / refusé / échoué). Anciennes propositions (held = false) : ancien comportement. Relançable.
alter table public.rc_trades add column if not exists held boolean not null default false;

create or replace function public.rc__trade_return(p_id bigint)
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare t public.rc_trades; it record;
begin
  select * into t from public.rc_trades where id = p_id;
  if t.id is null or not coalesce(t.held, false) then return; end if;
  for it in select * from public.rc__items(t.give) loop
    perform public.rc__give(t.sender, it.card, it.finish, it.n);
  end loop;
  update public.rc_trades set held = false where id = t.id;
  perform public.rc__rescore(t.sender);
end $function$;

create or replace FUNCTION public.rc_trade_offer(p_device text, p_to_pid text, p_give text, p_want text, p_sig text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare v_to text; v_id bigint; ng int; nw int; it record;
begin
  perform public.rc__check(p_sig, p_device || '|offer|' || p_to_pid || '|' || coalesce(p_give, '') || '|' || coalesce(p_want, ''));
  perform public.rc__not_new(p_device);
  perform public.rc__not_blocked(p_device);
  select device into v_to from public.rc_players where pid = p_to_pid;
  if v_to is null then raise exception 'joueur inconnu'; end if;
  if v_to = p_device then raise exception 'pas avec toi-même'; end if;
  select coalesce(sum(n), 0) into ng from public.rc__items(p_give);
  select coalesce(sum(n), 0) into nw from public.rc__items(p_want);
  if ng > 5 or nw > 5 or ng + nw = 0 then raise exception 'échange invalide'; end if;
  if exists (select 1 from public.rc__items(p_give) i where not exists (select 1 from public.rc_cards c where c.id = i.card))
     or exists (select 1 from public.rc__items(p_want) i where not exists (select 1 from public.rc_cards c where c.id = i.card)) then
    raise exception 'carte inconnue';
  end if;
  perform 1 from public.rc_players where device = p_device for update;
  if not public.rc__has(p_device, p_give) then raise exception 'tu ne possèdes pas ces cartes'; end if;
  if (select count(*) from public.rc_trades where sender = p_device and status = 'pending') >= 10 then
    raise exception 'trop d''échanges en attente';
  end if;
  -- les cartes proposées sortent du stock tant que l'échange est en attente (rendues si annulé / refusé / échoué)
  for it in select * from public.rc__items(p_give) loop
    if not public.rc__take(p_device, it.card, it.finish, it.n) then raise exception 'tu ne possèdes pas ces cartes'; end if;
  end loop;
  insert into public.rc_trades (sender, receiver, give, want, held) values (p_device, v_to, coalesce(p_give, ''), coalesce(p_want, ''), true)
  returning rc_trades.id into v_id;
  perform public.rc__rescore(p_device);
  return v_id;
end $function$;

create or replace function public.rc_trade_cancel(p_device text, p_id bigint, p_sig text)
 returns boolean
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare t public.rc_trades;
begin
  perform public.rc__check(p_sig, p_device || '|tcancel|' || p_id);
  select * into t from public.rc_trades where id = p_id and sender = p_device and status = 'pending' for update;
  if t.id is null then return false; end if;
  update public.rc_trades set status = 'cancelled', done_at = now() where id = t.id;
  perform public.rc__trade_return(t.id);
  return true;
end $function$;

create or replace function public.rc_trade_answer(p_device text, p_id bigint, p_accept boolean, p_sig text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare
  t public.rc_trades; it record; ev jsonb := '[]'::jsonb;
begin
  perform public.rc__check(p_sig, p_device || '|answer|' || p_id || '|' || p_accept);
  select * into t from public.rc_trades x where x.id = p_id and x.receiver = p_device and x.status = 'pending' for update;
  if t.id is null then raise exception 'échange introuvable'; end if;
  if p_accept then
    perform public.rc__not_blocked(t.sender);
    perform public.rc__not_blocked(t.receiver);
    perform public.rc__not_new(t.sender);
    perform public.rc__not_new(t.receiver);
  end if;
  if not p_accept then
    update public.rc_trades set status = 'refused', done_at = now() where id = t.id;
    perform public.rc__trade_return(t.id);
    return jsonb_build_object('status', 'refused');
  end if;
  -- verrouille les deux joueurs dans un ordre fixe (pas d'interblocage)
  perform 1 from public.rc_players where device in (t.sender, t.receiver) order by device for update;
  if not (coalesce(t.held, false) or public.rc__has(t.sender, t.give)) or not public.rc__has(t.receiver, t.want) then
    update public.rc_trades set status = 'failed', done_at = now() where id = t.id;
    perform public.rc__trade_return(t.id);
    return jsonb_build_object('status', 'failed');
  end if;
  for it in select * from public.rc__items(t.give) loop
    if not coalesce(t.held, false) then perform public.rc__take(t.sender, it.card, it.finish, it.n); end if;
    perform public.rc__give(t.receiver, it.card, it.finish, it.n);
  end loop;
  for it in select * from public.rc__items(t.want) loop
    perform public.rc__take(t.receiver, it.card, it.finish, it.n);
    perform public.rc__give(t.sender, it.card, it.finish, it.n);
  end loop;
  update public.rc_trades set status = 'accepted', done_at = now(), held = false where id = t.id;
  ev := ev || public.rc__bump(p_device, 'trade', 1) || public.rc__milestones(p_device);
  perform public.rc__bump(t.sender, 'trade', 1);
  perform public.rc__ev_bump(t.sender, 'trades', 1);    -- défi : échanges
  perform public.rc__ev_bump(t.receiver, 'trades', 1);
  perform public.rc__tbump(t.sender, 'trades', 1);    -- trophée : échanges
  perform public.rc__tbump(t.receiver, 'trades', 1);
  perform public.rc__milestones(t.sender);
  perform public.rc__rescore(t.sender);
  perform public.rc__rescore(t.receiver);
  return jsonb_build_object('status', 'accepted', 'events', ev);
end $function$;

-- la liste renvoie held : l'appli sait si mes cartes proposées sont déjà sorties du stock
drop function if exists public.rc_trades(text);
create or replace FUNCTION public.rc_trades(p_device text)
 RETURNS TABLE(id bigint, incoming boolean, other_name text, other_pid text, give text, want text, status text, created_at timestamp with time zone, done_at timestamp with time zone, held boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  (select t.id, t.receiver = p_device, o.name, o.pid, t.give, t.want, t.status, t.created_at, t.done_at, coalesce(t.held, false)
     from public.rc_trades t
     join public.rc_players o on o.device = case when t.receiver = p_device then t.sender else t.receiver end
    where (t.sender = p_device or t.receiver = p_device) and t.status = 'pending'
    order by t.created_at desc)
  union all
  (select t.id, t.receiver = p_device, o.name, o.pid, t.give, t.want, t.status, t.created_at, t.done_at, coalesce(t.held, false)
     from public.rc_trades t
     join public.rc_players o on o.device = case when t.receiver = p_device then t.sender else t.receiver end
    where (t.sender = p_device or t.receiver = p_device) and t.status <> 'pending'
    order by t.done_at desc nulls last
    limit 20) $function$;

alter function public.rc_trades(text) owner to rc_owner;
grant execute on function public.rc_trades(text) to anon, authenticated;
alter function public.rc__trade_return(bigint) owner to rc_owner;
alter function public.rc_trade_offer(text, text, text, text, text) owner to rc_owner;
alter function public.rc_trade_cancel(text, bigint, text) owner to rc_owner;
alter function public.rc_trade_answer(text, bigint, boolean, text) owner to rc_owner;

notify pgrst, 'reload schema';

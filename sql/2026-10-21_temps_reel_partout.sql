-- 2026-10-21 : temps réel partout (1.0.18).
-- En plus des duels, le serveur prévient l'appli via le relais rc-realtime :
--  · canal du joueur (rc__rt_topic(device)), événement 'me' {k} :
--      trade (proposition reçue / répondue), sale (carte vendue), gift (paquet reçu)
--      → l'appli relit ses notifications (rc_notifs).
--  · canal commun 'rc_all' (rien de secret : juste « ça a bougé ») :
--      chat, feed, market, config, online → l'écran concerné se recharge.
-- Pas de contenu dans les messages : l'appli relit par les RPC habituelles.
-- pg_notify regroupe les messages identiques d'une même transaction.
-- Si l'envoi échoue, le jeu n'est jamais bloqué. Relançable.

-- ─── Envoi sans risque ────────────────────────────────────────────────────
create or replace function public.rc__rt_safe(p_topic text, p_event text, p_payload jsonb)
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
begin
  perform public.rc__rt_send(p_topic, p_event, p_payload);
exception when others then
  null; -- relais indisponible : le polling de secours prend le relais
end $function$;

-- ─── Canal commun : un déclencheur par instruction ────────────────────────
create or replace function public.rc__rt_all()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
begin
  perform public.rc__rt_safe('rc_all', tg_argv[0], '{}'::jsonb);
  return null;
end $function$;

create or replace trigger rc_chat_rt after insert or update on public.rc_chat
  for each statement execute function public.rc__rt_all('chat');
create or replace trigger rc_feed_rt after insert on public.rc_feed
  for each statement execute function public.rc__rt_all('feed');
create or replace trigger rc_market_rt after insert or update or delete on public.rc_market
  for each statement execute function public.rc__rt_all('market');
create or replace trigger rc_config_rt after insert or update or delete on public.rc_config
  for each statement execute function public.rc__rt_all('config');

-- Un joueur arrive en ligne (seen_at repart après plus de 75 s d'absence)
create or replace trigger rc_players_online_rt after update of seen_at on public.rc_players
  for each row
  when (new.seen_at is not null and (old.seen_at is null or old.seen_at < now() - interval '75 seconds'))
  execute function public.rc__rt_all('online');

-- ─── Canal du joueur ──────────────────────────────────────────────────────
create or replace function public.rc__rt_me()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
begin
  if tg_table_name = 'rc_trades' then
    if tg_op = 'INSERT' then
      perform public.rc__rt_safe(public.rc__rt_topic(new.receiver), 'me', '{"k":"trade"}');
    elsif new.status is distinct from old.status then
      perform public.rc__rt_safe(public.rc__rt_topic(new.sender), 'me', '{"k":"trade"}');
      perform public.rc__rt_safe(public.rc__rt_topic(new.receiver), 'me', '{"k":"trade"}');
    end if;
  elsif tg_table_name = 'rc_market' then
    if new.buyer is not null and old.buyer is null then
      perform public.rc__rt_safe(public.rc__rt_topic(new.seller), 'me', '{"k":"sale"}');
    end if;
  elsif tg_table_name = 'rc_gifts' then
    perform public.rc__rt_safe(public.rc__rt_topic(new.receiver), 'me', '{"k":"gift"}');
  end if;
  return null;
exception when others then
  return null;
end $function$;

create or replace trigger rc_trades_rt after insert or update on public.rc_trades
  for each row execute function public.rc__rt_me();
create or replace trigger rc_market_sale_rt after update of buyer on public.rc_market
  for each row execute function public.rc__rt_me();
create or replace trigger rc_gifts_rt after insert on public.rc_gifts
  for each row execute function public.rc__rt_me();

-- ─── Propriétaire et droits ───────────────────────────────────────────────
alter function public.rc__rt_safe(text, text, jsonb) owner to rc_owner;
alter function public.rc__rt_all() owner to rc_owner;
alter function public.rc__rt_me() owner to rc_owner;
revoke execute on function public.rc__rt_safe(text, text, jsonb) from public, anon, authenticated;
revoke execute on function public.rc__rt_all() from public, anon, authenticated;
revoke execute on function public.rc__rt_me() from public, anon, authenticated;

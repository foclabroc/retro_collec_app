-- 2026-10-21 : Realtime pour les duels (4 en ligne, Console Wars).
-- À chaque création / modification d'une partie (rc_c4, rc_bs), le serveur envoie
-- un message Broadcast {game, gid, status} aux deux joueurs, chacun sur son canal :
-- 'rc_' + sha256('rt|' + device)[0..24] (déduit du device SECRET, jamais du pid).
-- L'appli (lib/live_link.dart) recharge alors tout de suite ; le polling reste en secours.
-- Si l'envoi échoue, la partie n'est jamais bloquée. Relançable.

create or replace function public.rc__rt_topic(p_device text)
 returns text
 language sql
 immutable
 set search_path to 'public', 'extensions'
as $function$
  select 'rc_' || left(encode(extensions.digest('rt|' || p_device, 'sha256'), 'hex'), 24) $function$;

create or replace function public.rc__rt_duel()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare msg jsonb;
begin
  -- clé 'gid' (et pas 'id' : realtime.send s'en servirait comme identifiant du message)
  msg := jsonb_build_object('game', tg_argv[0], 'gid', new.id, 'status', new.status);
  begin
    if new.p1 is not null then perform realtime.send(msg, 'duel', public.rc__rt_topic(new.p1), false); end if;
    if new.p2 is not null then perform realtime.send(msg, 'duel', public.rc__rt_topic(new.p2), false); end if;
  exception when others then
    null; -- Realtime indisponible : le polling de secours prend le relais
  end;
  return null;
end $function$;

create or replace trigger rc_c4_rt after insert or update on public.rc_c4
  for each row execute function public.rc__rt_duel('c4');

create or replace trigger rc_bs_rt after insert or update on public.rc_bs
  for each row execute function public.rc__rt_duel('bs');

-- fonctions internes : pas appelables depuis l'API
revoke execute on function public.rc__rt_topic(text) from public, anon, authenticated;
revoke execute on function public.rc__rt_duel() from public, anon, authenticated;

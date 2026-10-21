-- ═══════════════════════════════════════════════════════════════════════════
-- Pixel Trade auto-hébergé — étape 2 : à lancer APRÈS l'import de la sauvegarde.
-- Branche les duels sur le relais rc-realtime et vérifie la sécurité. Relançable.
-- ═══════════════════════════════════════════════════════════════════════════

-- Temps réel : realtime.send (Supabase) remplacé par pg_notify vers le relais.
-- Même message qu'avant ({game, gid, status}, évènement « duel », canal du joueur) :
-- live_link.dart ne voit aucune différence.
create or replace function public.rc__rt_send(p_topic text, p_event text, p_payload jsonb)
 returns void
 language sql
 security definer
 set search_path to 'public'
as $function$
  select pg_notify('rc_rt', jsonb_build_object('topic', p_topic, 'event', p_event, 'payload', p_payload)::text);
$function$;

create or replace function public.rc__rt_duel()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare msg jsonb;
begin
  msg := jsonb_build_object('game', tg_argv[0], 'gid', new.id, 'status', new.status);
  begin
    if new.p1 is not null then perform public.rc__rt_send(public.rc__rt_topic(new.p1), 'duel', msg); end if;
    if new.p2 is not null then perform public.rc__rt_send(public.rc__rt_topic(new.p2), 'duel', msg); end if;
  exception when others then
    null; -- relais indisponible : le polling de secours prend le relais
  end;
  return null;
end $function$;

-- Sécurité : les fonctions internes « rc__… » ne doivent jamais être appelables
-- depuis l'API (comme chez Supabase). Les RPC « rc_… » les appellent en tant que propriétaire.
do $$
declare f record;
begin
  for f in
    select p.oid::regprocedure as sig
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname like 'rc\_\_%'
  loop
    execute format('revoke execute on function %s from public, anon, authenticated', f.sig);
  end loop;
end $$;

-- Contrôle : doit renvoyer 0
select count(*) as fonctions_internes_ouvertes
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname like 'rc\_\_%' and has_function_privilege('anon', p.oid, 'execute');

-- PostgREST : recharge la liste des fonctions
notify pgrst, 'reload schema';

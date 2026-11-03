create or replace function public.rc__not_blocked(p_dev text)
 returns void language plpgsql security definer set search_path to 'public' as $$
declare u timestamptz;
begin
  if exists (select 1 from public.rc_players where device = p_dev and blocked) then
    raise exception 'compte bloqué : échanges, ventes, achats, cadeaux, duels et tournois désactivés';
  end if;
  u := public.rc__sanction_until(p_dev, 'duel');
  if u is not null then
    raise exception 'duels et tournois suspendus %',
      case when u = 'infinity' then 'pour ce compte' else 'jusqu''au ' || to_char(u at time zone 'Europe/Paris', 'DD/MM à HH24"h"MI') end;
  end if;
end $$;

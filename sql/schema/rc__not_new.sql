create or replace function public.rc__not_new(p_device text)
 returns void language plpgsql security definer set search_path to 'public' as $$
declare u timestamptz;
begin
  if exists (select 1 from public.rc_players where device = p_device and created_at > now() - interval '24 hours') then
    raise exception 'compte trop récent : possible 24 h après la création du compte';
  end if;
  u := public.rc__sanction_until(p_device, 'trade');
  if u is not null then
    raise exception 'Bourse, cadeaux et échanges suspendus %',
      case when u = 'infinity' then 'pour ce compte' else 'jusqu''au ' || to_char(u at time zone 'Europe/Paris', 'DD/MM à HH24"h"MI') end;
  end if;
end $$;

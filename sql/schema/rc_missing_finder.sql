-- Mes cartes manquantes que les voisins ont en double (vus depuis 30 jours) : un bloc par joueur,
-- du joueur qui en a le plus au moins ; cartes de la plus rare à la plus commune. Relançable.
create or replace function public.rc_missing_finder(p_device text, p_sig text)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to 'public'
as $function$
begin
  perform public.rc__check(p_sig, p_device || '|missing');
  return (
    with mine as (
      select distinct card from public.rc_owned where device = p_device and qty > 0
    ), dbl as (
      select o.device, o.card, sum(o.qty)::int as q
        from public.rc_owned o
       where o.device <> p_device and not exists (select 1 from mine m where m.card = o.card)
       group by o.device, o.card
      having sum(o.qty) >= 2
    ), per as (
      select p.pid, p.name, p.avatar, (p.seen_at > now() - interval '75 seconds') as online, count(*)::int as n,
             jsonb_agg(jsonb_build_array(d.card, d.q) order by c.rarity desc, d.card) as cards
        from dbl d
        join public.rc_players p on p.device = d.device
        join public.rc_cards c on c.id = d.card
       where p.seen_at > now() - interval '30 days'
       group by p.pid, p.name, p.avatar, p.seen_at
       order by count(*) desc, p.seen_at desc
       limit 40
    )
    select jsonb_build_object(
             'cards', (select count(distinct d.card) from dbl d join public.rc_players p on p.device = d.device
                        where p.seen_at > now() - interval '30 days'),
             'players', coalesce((select jsonb_agg(to_jsonb(per) order by per.n desc) from per), '[]'::jsonb))
  );
end $function$;

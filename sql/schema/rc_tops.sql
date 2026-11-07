-- Onglet « Tops » de l'Actualité (appli) : mêmes classements que la page Stats › Tops de l'outil admin,
-- ouverts à tous (sans signature : seulement pseudos, avatars et nombres), 10 premiers, joueurs bloqués exclus.
-- p_days : 1 (aujourd'hui), 7 ou 30 (rc_activity ne garde que 30 jours). « Cartes » = total actuel.

-- {device: nombre} → [{pid, name, avatar, n}] des 10 premiers (interne)
create or replace function public.rc__tops_list(p jsonb)
 returns jsonb language sql stable security definer set search_path to 'public'
as $$
  select coalesce(jsonb_agg(jsonb_build_object('pid', x.pid, 'name', x.name, 'avatar', x.avatar, 'n', x.n) order by x.n desc, x.name), '[]'::jsonb)
    from (select p.pid, p.name, p.avatar, e.value::numeric n
            from jsonb_each_text(coalesce(p, '{}'::jsonb)) e
            join public.rc_players p on p.device = e.key
           where not coalesce(p.blocked, false) and e.value::numeric > 0
           order by e.value::numeric desc, p.name limit 10) x
$$;

CREATE OR REPLACE FUNCTION public.rc_tops(p_days integer DEFAULT 7)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare v_days int := least(greatest(coalesce(p_days, 7), 1), 30); since timestamptz;
begin
  since := (rc__today() - (v_days - 1))::timestamp at time zone 'Europe/Paris';
  return jsonb_build_object(
    'days', v_days,
    'packs', rc__tops_list((select jsonb_object_agg(device, n) from (select device, count(*) n from rc_pack_log where at >= since group by device) x)),
    'gain', rc__tops_list((select jsonb_object_agg(device, n) from (select device, sum(coins) n from rc_activity where coins > 0 and at >= since group by device) x)),
    'wins', rc__tops_list((select jsonb_object_agg(d, n) from (select d, count(*) n from (
               select case when winner = 1 then p1 else p2 end d, move_at from rc_c4 where status = 'done' and winner in (1, 2)
               union all select case when winner = 1 then p1 else p2 end, move_at from rc_bs where status = 'done' and winner in (1, 2)
               union all select case when winner = 1 then p1 else p2 end, move_at from rc_rj where status = 'done' and winner in (1, 2)) w
              where move_at >= since group by d) x)),
    'market', rc__tops_list((select jsonb_object_agg(d, n) from (select d, sum(price) n from (
               select seller d, price, sold_at from rc_market where buyer is not null
               union all select buyer, price, sold_at from rc_market where buyer is not null) m
              where sold_at >= since group by d) x)),
    'gifts', rc__tops_list((select jsonb_object_agg(giver, n) from (select giver, count(*) n from rc_gifts where giver is not null and created_at >= since group by giver) x)),
    'cards', rc__tops_list((select jsonb_object_agg(device, cards) from rc_players where cards > 0)),
    -- ajoutés le 7/11
    'score', rc__tops_list((select jsonb_object_agg(device, score) from rc_players where score > 0)),
    'series', rc__tops_list((select jsonb_object_agg(device, n) from (select device, count(distinct card) n from rc_owned
               where qty > 0 and card ~ '^(pk|da|db)_' group by device) x)),
    'trophies', rc__tops_list((select jsonb_object_agg(device, n) from (select device, sum(tier) n from rc_trophy_got
               where tier > 0 group by device) x)),
    'boosters', rc__tops_list((select jsonb_object_agg(device, n) from (select device, count(*) n from rc_pack_log
               where at >= since and kind in ('pokemon', 'cartoon', 'dragonball', 'premium', 'star', 'gold') group by device) x)),
    'rj', rc__tops_list((select jsonb_object_agg(device, n) from (select device, max(score) n from rc_rj_best
               where day >= rc__today() - (v_days - 1) group by device) x)),
    'rn', rc__tops_list((select jsonb_object_agg(device, n) from (select device, max(score) n from rc_rn_best
               where day >= rc__today() - (v_days - 1) group by device) x)));
end $function$;

alter function public.rc__tops_list(jsonb) owner to rc_owner;
alter function public.rc_tops(int) owner to rc_owner;
grant execute on function public.rc_tops(int) to anon, authenticated;

notify pgrst, 'reload schema';

-- Tops de l'Actualité : 6 classements de plus   (relançable)
--   score de collection, cartes de séries (Pokémon + Dessins animés + Dragon Ball), trophées (paliers),
--   boosters spéciaux ouverts (période), meilleur Rétro Jump solo (période), meilleure Course de jaquettes (période)
create or replace function public.rc_tops(p_days int default 7)
 returns jsonb language plpgsql stable security definer set search_path to 'public', 'extensions'
as $$
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
end $$;

alter function public.rc_tops(int) owner to rc_owner;
grant execute on function public.rc_tops(int) to anon, authenticated;

notify pgrst, 'reload schema';

select jsonb_object_keys(public.rc_tops(7)) as classements;

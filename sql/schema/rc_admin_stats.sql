CREATE OR REPLACE FUNCTION public.rc_admin_stats(p_device text, p_sig text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare today date := public.rc__today();
begin
  perform public.rc__admin(p_device, p_sig, 'stats');
  return jsonb_build_object(
    'players', (select count(*) from public.rc_players where packs > 0),
    'active7', (select count(*) from public.rc_players where seen_at > now() - interval '7 days'),
    'today', (select count(*) from public.rc_players where (seen_at at time zone 'Europe/Paris')::date = today),
    'new7', (select count(*) from public.rc_players where created_at > now() - interval '7 days'),
    'packs_today', coalesce((select packs from public.rc_daily where day = today), 0),
    'sales_today', (select count(*) from public.rc_market where buyer is not null and (sold_at at time zone 'Europe/Paris')::date = today),
    'market_open', (select count(*) from public.rc_market where buyer is null),
    'duels_today', (select count(*) from (select status, reason, move_at from public.rc_c4 union all select status, reason, move_at from public.rc_bs) d
                     where d.status = 'done' and coalesce(d.reason, '') not in ('declined', 'cancelled', 'expired')
                       and (d.move_at at time zone 'Europe/Paris')::date = today),
    'coins', (select coalesce(sum(coins), 0) from public.rc_players),
    'pixels', (select coalesce(sum(pixels), 0) from public.rc_players),
    'saga', (select coalesce(sum(qty), 0) from public.rc_owned where card like 'sg\_%'),
    'rich', coalesce((select jsonb_agg(jsonb_build_object('name', name, 'pid', pid, 'coins', coins) order by coins desc)
                        from (select name, pid, coins from public.rc_players order by coins desc limit 3) r), '[]'::jsonb),
    'days', coalesce((select jsonb_agg(jsonb_build_object('day', d.day::date, 'players', coalesce(x.players, 0), 'packs', coalesce(x.packs, 0)) order by d.day)
                        from generate_series(today - 6, today, interval '1 day') d(day)
                        left join public.rc_daily x on x.day = d.day::date), '[]'::jsonb));
end $function$

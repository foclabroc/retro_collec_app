-- Admin : journal de TOUS les joueurs (même contenu que l'activité d'une fiche joueur),
-- du plus récent au plus ancien, 150 lignes par page (p_before = date de la dernière ligne reçue, '' = début).
-- Relançable.
create or replace function public.rc_admin_feed(p_device text, p_sig text, p_before text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare b timestamptz;
begin
  perform public.rc__admin(p_device, p_sig, 'feed|' || coalesce(p_before, ''));
  b := case when coalesce(p_before, '') = '' then now() + interval '1 minute' else p_before::timestamptz end;
  return coalesce((
    select jsonb_agg(
             r.e || jsonb_build_object('at', r.at, 'pid', p.pid, 'name', p.name, 'avatar', p.avatar,
                                       'other', coalesce(o.name, r.e->>'other'))
                 || case when r.e->>'kind' = 'sold'
                         then jsonb_build_object('avg', public.rc__avg_price(r.e->>'card', (r.e->>'f')::int, (r.e->>'mid')::bigint))
                         else '{}'::jsonb end
             order by r.at desc)
      from (
        select * from (
          -- Bourse : mise en vente (pas vendue) ou vente conclue, vue du vendeur
          select coalesce(m.sold_at, m.created_at) at, m.seller dev, m.buyer odev,
                 jsonb_build_object('kind', case when m.buyer is null then 'listing' else 'sold' end,
                                    'card', m.card, 'f', m.finish, 'price', m.price, 'mid', m.id) e
            from public.rc_market m
           where coalesce(m.sold_at, m.created_at) < b
          union all
          -- échanges, vus de celui qui propose
          select coalesce(t.done_at, t.created_at), t.sender, t.receiver,
                 jsonb_build_object('kind', 'trade', 'status', t.status, 'gave', t.give, 'got', t.want,
                                    'gave_v', public.rc__items_value(t.give), 'got_v', public.rc__items_value(t.want))
            from public.rc_trades t
           where coalesce(t.done_at, t.created_at) < b
          union all
          -- cadeaux, vus de celui qui offre
          select g.created_at, g.giver, g.receiver, jsonb_build_object('kind', 'gift_out', 'other', g.giver_name)
            from public.rc_gifts g
           where g.created_at < b
          union all
          -- duels, vus du joueur 1
          select x.created_at, x.p1, x.p2,
                 jsonb_build_object('kind', 'duel', 'game', x.jeu, 'status', x.status, 'reason', x.reason,
                                    'result', case when x.winner = 0 then 'draw' when x.winner is null then null
                                                   when x.winner = 1 then 'win' else 'loss' end)
            from (select 'c4' jeu, p1, p2, status, reason, winner, created_at from public.rc_c4
                  union all select 'bs', p1, p2, status, reason, winner, created_at from public.rc_bs) x
           where x.created_at < b
          union all
          select c.created_at, c.device, null::text,
                 jsonb_build_object('kind', 'chat', 'msg', c.msg, 'hidden', c.hidden, 'reports', c.reports)
            from public.rc_chat c
           where c.created_at < b
          union all
          select l.at, l.device, null::text, jsonb_build_object('kind', 'pack', 'pack', l.kind, 'sys', l.sys)
            from public.rc_pack_log l
           where l.at < b
        ) u
        order by u.at desc
        limit 150
      ) r
      left join public.rc_players p on p.device = r.dev
      left join public.rc_players o on o.device = r.odev), '[]'::jsonb);
end $function$;

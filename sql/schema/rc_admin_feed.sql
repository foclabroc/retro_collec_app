-- Admin : journal de TOUS les joueurs (même contenu que l'activité d'une fiche joueur),
-- du plus récent au plus ancien, 150 lignes par page (p_before = date de la dernière ligne reçue, '' = début).
-- Avec les courriers / cadeaux de l'admin (envoi + récupération) depuis le 22/10. Relançable.
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
          -- cadeaux, vus de celui qui offre ; cadeau du jeu (sans donneur : défis, courrier, parrainage…) vu de celui qui le reçoit
          select g.created_at, coalesce(g.giver, g.receiver), case when g.giver is null then null else g.receiver end,
                 jsonb_build_object('kind', case when g.giver is null then 'gift_in' else 'gift_out' end,
                                    'other', case when g.giver is null then g.giver_name end)
            from public.rc_gifts g
           where g.created_at < b
          union all
          -- duels, vus du joueur 1
          select x.created_at, x.p1, x.p2,
                 jsonb_build_object('kind', 'duel', 'game', x.jeu, 'status', x.status, 'reason', x.reason,
                                    'result', case when x.winner = 0 then 'draw' when x.winner is null then null
                                                   when x.winner = 1 then 'win' else 'loss' end)
            from (select 'c4' jeu, p1, p2, status, reason, winner, created_at from public.rc_c4
                  union all select 'bs', p1, p2, status, reason, winner, created_at from public.rc_bs
                  union all select 'rj', p1, p2, status, reason, winner, created_at from public.rc_rj) x
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
          union all
          -- courrier / cadeau de l'admin : envoi, vu du destinataire (sans joueur = envoi à un groupe)
          select m.created_at, m.device, null::text,
                 jsonb_build_object('kind', 'mail_sent', 'title', m.title,
                                    'grp', coalesce(m.grp, case when m.device is null then 'all' end),
                                    'reward', case when coalesce(m.reward, '{}'::jsonb) = '{}'::jsonb
                                                   then jsonb_strip_nulls(jsonb_build_object(
                                                          'coins', nullif(m.coins, 0), 'pixels', nullif(m.pixels, 0),
                                                          'packs', case when m.packs > 0 then jsonb_build_object('premium', m.packs) end))
                                                   else m.reward end)
            from public.rc_mail m
           where m.created_at < b
          union all
          -- courrier récupéré par le joueur (journal d'activité : pièces / pixels versés)
          select a.at, a.device, null::text,
                 jsonb_build_object('kind', 'mail_got', 'txt', a.txt, 'coins', a.coins, 'pixels', a.pixels)
            from public.rc_activity a
           where a.at < b and a.at > now() - interval '30 days' and a.txt like 'récupère le courrier%'
        ) u
        order by u.at desc
        limit 150
      ) r
      left join public.rc_players p on p.device = r.dev
      left join public.rc_players o on o.device = r.odev), '[]'::jsonb);
end $function$;

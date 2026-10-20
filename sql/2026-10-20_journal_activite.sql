-- ═══════════════════════════════════════════════════════════════════════════
-- PIXEL TRADE — Journal d'activité des joueurs (page admin)       (relançable)
-- Tout est rempli par des déclencheurs : aucune fonction du jeu n'est modifiée.
-- Une action = une ligne par joueur (même transaction regroupée), avec le
-- mouvement de pièces / pixels. Tout mouvement non reconnu apparaît en « 💰 ».
-- Gardé 30 jours. Le chat n'y est pas.
-- ═══════════════════════════════════════════════════════════════════════════

create table if not exists public.rc_activity (
  id     bigserial   primary key,
  at     timestamptz not null default now(),
  tx     bigint      not null default txid_current(),
  device text        not null,
  kind   text        not null,
  prio   int         not null default 0,
  txt    text        not null default '',
  card   text,
  finish int,
  other  text,
  coins  int         not null default 0,
  pixels int         not null default 0
);
create index if not exists rc_activity_tx   on public.rc_activity (tx, device);
create index if not exists rc_activity_dev  on public.rc_activity (device, id);
create index if not exists rc_activity_kind on public.rc_activity (kind, id);
create index if not exists rc_activity_at   on public.rc_activity (at);
alter table public.rc_activity enable row level security;

-- rc__act : ajoute une ligne, ou complète celle du même joueur dans la même transaction
-- (le libellé le plus précis gagne : 0 pièces seules, 1 deviné par le compte, 2 action connue ;
--  deux actions connues gardent chacune leur ligne)
create or replace function public.rc__act(p_dev text, p_kind text, p_prio int, p_txt text,
                                          p_card text default null, p_f int default null, p_other text default null,
                                          p_dc int default 0, p_dp int default 0)
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare r record; v_id bigint;
begin
  if p_dev is null then return; end if;
  select id, prio into r from public.rc_activity
   where tx = txid_current() and device = p_dev order by id desc limit 1;
  if found and (r.prio < 2 or p_prio < 2) then  -- deux actions connues restent sur deux lignes
    update public.rc_activity
       set coins = coins + coalesce(p_dc, 0), pixels = pixels + coalesce(p_dp, 0),
           kind  = case when p_prio > r.prio then p_kind  else kind  end,
           txt   = case when p_prio > r.prio then p_txt   else txt   end,
           card  = case when p_prio > r.prio then p_card  else card  end,
           finish= case when p_prio > r.prio then p_f     else finish end,
           other = case when p_prio > r.prio then p_other else other end,
           prio  = greatest(prio, p_prio)
     where id = r.id;
  else
    insert into public.rc_activity (device, kind, prio, txt, card, finish, other, coins, pixels)
    values (p_dev, p_kind, p_prio, coalesce(p_txt, ''), p_card, p_f, p_other, coalesce(p_dc, 0), coalesce(p_dp, 0))
    returning id into v_id;
    if v_id % 500 = 0 then delete from public.rc_activity where at < now() - interval '30 days'; end if;
  end if;
exception when others then null;  -- le journal ne doit jamais bloquer le jeu
end $function$;

-- ── Joueurs : inscription, connexion du jour, roue, défis, quiz, lots, pièces ──
create or replace function public.rc__act_players()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare dc int := 0; dp int := 0; k text; t text; p int := 1;
begin
  begin
    if tg_op = 'INSERT' then
      perform public.rc__act(new.device, 'join', 2, 'crée son compte');
      return new;
    end if;
    dc := coalesce(new.coins, 0) - coalesce(old.coins, 0);
    dp := coalesce(new.pixels, 0) - coalesce(old.pixels, 0);
    if new.last_login is distinct from old.last_login then
      k := 'login'; t := 'connexion du jour (série ' || coalesce((to_jsonb(new) ->> 'streak'), '?') || ')';
    elsif new.wheel_day is distinct from old.wheel_day then
      k := 'wheel'; t := 'tourne la roue';
    elsif new.w_claim is distinct from old.w_claim then
      k := 'week';
      t := case when (coalesce(new.w_claim, 0) & 64) <> 0 and (coalesce(old.w_claim, 0) & 64) = 0
                then 'ouvre le coffre des défis' else 'récupère un défi de la semaine' end;
    elsif new.quiz_day is distinct from old.quiz_day or (to_jsonb(new) ->> 'quiz_gain') is distinct from (to_jsonb(old) ->> 'quiz_gain') then
      k := 'quiz'; t := 'quiz';
    elsif coalesce(new.lots, 0) > coalesce(old.lots, 0) then
      k := 'lot'; t := 'achète un lot de ' || (new.lots - coalesce(old.lots, 0)) || ' paquets';
    elsif coalesce(new.packs, 0) > coalesce(old.packs, 0) then
      k := 'open'; t := 'ouvre son paquet';
    elsif dc <> 0 or dp <> 0 then
      k := 'coins'; t := 'mouvement'; p := 0;
    else
      return new;
    end if;
    perform public.rc__act(new.device, k, p, t, null, null, null, dc, dp);
  exception when others then null;
  end;
  return new;
end $function$;

drop trigger if exists rc_act_players_ins on public.rc_players;
create trigger rc_act_players_ins after insert on public.rc_players
  for each row execute function public.rc__act_players();
drop trigger if exists rc_act_players_upd on public.rc_players;
create trigger rc_act_players_upd after update on public.rc_players
  for each row when (old.coins is distinct from new.coins or old.pixels is distinct from new.pixels
                  or old.last_login is distinct from new.last_login or old.wheel_day is distinct from new.wheel_day
                  or old.w_claim is distinct from new.w_claim or old.quiz_day is distinct from new.quiz_day
                  or old.lots is distinct from new.lots or old.packs is distinct from new.packs)
  execute function public.rc__act_players();

-- ── Paquets : choix + paiement (rc_pending) ──────────────────────────────────
create or replace function public.rc__act_pack()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare j jsonb := to_jsonb(new); n int := coalesce((j ->> 'packs')::int, 1);
begin
  begin
    perform public.rc__act(new.device, 'pack', 2,
      'prend ' || case when n > 1 then n || ' paquets ' else 'un paquet ' end || coalesce(j ->> 'kind', '?')
      || coalesce(' (' || nullif(j ->> 'sys', '') || ')', ''));
  exception when others then null;
  end;
  return new;
end $function$;

drop trigger if exists rc_act_pack on public.rc_pending;
create trigger rc_act_pack after insert on public.rc_pending
  for each row execute function public.rc__act_pack();

-- ── Bourse : mise en vente, vente / achat, retrait ───────────────────────────
create or replace function public.rc__act_market()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
begin
  begin
    if tg_op = 'INSERT' then
      perform public.rc__act(new.seller, 'sell', 2, 'met en vente à ' || new.price || ' pièces', new.card, new.finish);
    elsif tg_op = 'UPDATE' then
      if new.buyer is not null and old.buyer is null then
        perform public.rc__act(new.buyer,  'buy',  2, 'achète à ' || new.price || ' pièces à', new.card, new.finish, new.seller);
        perform public.rc__act(new.seller, 'sold', 2, 'vend à ' || new.price || ' pièces à', new.card, new.finish, new.buyer);
      end if;
    elsif old.buyer is null then
      perform public.rc__act(old.seller, 'unsell', 2, 'retire de la Bourse', old.card, old.finish);
      return old;
    end if;
  exception when others then null;
  end;
  return coalesce(new, old);
end $function$;

drop trigger if exists rc_act_market on public.rc_market;
create trigger rc_act_market after insert or update or delete on public.rc_market
  for each row execute function public.rc__act_market();

-- ── Échanges ─────────────────────────────────────────────────────────────────
create or replace function public.rc__act_trade()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare g int; w int; s text;
begin
  begin
    g := coalesce(array_length(array_remove(string_to_array(coalesce(new.give, ''), ','), ''), 1), 0);
    w := coalesce(array_length(array_remove(string_to_array(coalesce(new.want, ''), ','), ''), 1), 0);
    s := g || ' carte' || case when g > 1 then 's' else '' end || ' contre ' || w;
    if tg_op = 'INSERT' then
      perform public.rc__act(new.sender, 'trade_offer', 2, 'propose un échange (' || s || ') à', null, null, new.receiver);
    elsif new.status is distinct from old.status then
      if new.status = 'accepted' then
        perform public.rc__act(new.sender,   'trade_ok', 2, 'échange accepté (' || s || ') avec', null, null, new.receiver);
        perform public.rc__act(new.receiver, 'trade_ok', 2, 'accepte l''échange (' || s || ') de', null, null, new.sender);
      elsif new.status = 'refused' then
        perform public.rc__act(new.receiver, 'trade_no', 2, 'refuse l''échange de', null, null, new.sender);
      elsif new.status = 'cancelled' then
        perform public.rc__act(new.sender, 'trade_no', 2, 'annule son échange avec', null, null, new.receiver);
      elsif new.status = 'failed' then
        perform public.rc__act(new.receiver, 'trade_no', 2, 'échange impossible (cartes plus là) avec', null, null, new.sender);
      end if;
    end if;
  exception when others then null;
  end;
  return new;
end $function$;

drop trigger if exists rc_act_trade on public.rc_trades;
create trigger rc_act_trade after insert or update on public.rc_trades
  for each row execute function public.rc__act_trade();

-- ── Cadeaux ──────────────────────────────────────────────────────────────────
create or replace function public.rc__act_gift()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
begin
  begin
    if new.giver is not null and exists (select 1 from public.rc_players where device = new.giver) then
      perform public.rc__act(new.giver, 'gift', 2, 'offre un paquet cadeau à', null, null, new.receiver);
    else
      perform public.rc__act(new.receiver, 'gift_in', 2,
        'reçoit un cadeau' || coalesce(' de « ' || nullif(new.giver_name, '') || ' »', ''));
    end if;
  exception when others then null;
  end;
  return new;
end $function$;

drop trigger if exists rc_act_gift on public.rc_gifts;
create trigger rc_act_gift after insert on public.rc_gifts
  for each row execute function public.rc__act_gift();

-- ── Duels : 4 en ligne (rc_c4) et Console Wars (rc_bs) ───────────────────────
create or replace function public.rc__act_duel()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare jeu text := case when tg_table_name = 'rc_bs' then 'Console Wars' else '4 en ligne' end;
        how text; ami text;
begin
  begin
    if tg_op = 'INSERT' then
      perform public.rc__act(new.p1, 'duel', 2, 'invite à ' || jeu, null, null, new.p2);
    elsif new.status = 'done' and old.status is distinct from 'done' then
      if new.reason in ('win', 'draw', 'timeout', 'resign') then
        how := case new.reason when 'timeout' then ' (temps écoulé)' when 'resign' then ' (abandon)' else '' end;
        ami := case when coalesce(new.paid, false) then '' else ' — amical' end;
        if new.winner in (1, 2) then
          perform public.rc__act(case new.winner when 1 then new.p1 else new.p2 end, 'duel', 2,
                                 'gagne à ' || jeu || how || ami || ' contre', null, null,
                                 case new.winner when 1 then new.p2 else new.p1 end);
          perform public.rc__act(case new.winner when 1 then new.p2 else new.p1 end, 'duel', 2,
                                 'perd à ' || jeu || how || ami || ' contre', null, null,
                                 case new.winner when 1 then new.p1 else new.p2 end);
        else
          perform public.rc__act(new.p1, 'duel', 2, 'match nul à ' || jeu || ami || ' contre', null, null, new.p2);
          perform public.rc__act(new.p2, 'duel', 2, 'match nul à ' || jeu || ami || ' contre', null, null, new.p1);
        end if;
      elsif new.reason = 'declined' then
        perform public.rc__act(new.p2, 'duel', 2, 'refuse le ' || jeu || ' de', null, null, new.p1);
      elsif new.reason = 'cancelled' then
        perform public.rc__act(new.p1, 'duel', 2, 'annule son invitation à ' || jeu || ' pour', null, null, new.p2);
      end if;
    end if;
  exception when others then null;
  end;
  return new;
end $function$;

drop trigger if exists rc_act_c4 on public.rc_c4;
create trigger rc_act_c4 after insert or update of status on public.rc_c4
  for each row execute function public.rc__act_duel();
drop trigger if exists rc_act_bs on public.rc_bs;
create trigger rc_act_bs after insert or update of status on public.rc_bs
  for each row execute function public.rc__act_duel();

-- ── Gamedle trouvé ───────────────────────────────────────────────────────────
create or replace function public.rc__act_gamedle()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
begin
  begin
    if coalesce(new.won, false) and not coalesce(old.won, false) then
      perform public.rc__act(new.device, 'gamedle', 2,
        'trouve le Gamedle en ' || coalesce(array_length(new.guesses, 1), 0) || ' essai(s)');
    end if;
  exception when others then null;
  end;
  return new;
end $function$;

drop trigger if exists rc_act_gamedle on public.rc_gamedle;
create trigger rc_act_gamedle after update on public.rc_gamedle
  for each row execute function public.rc__act_gamedle();

-- ── Récompenses : événement, trophée, palier, courrier, collection ───────────
create or replace function public.rc__act_reward()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare j jsonb := to_jsonb(new); t text;
begin
  begin
    t := case tg_table_name
      when 'rc_events_got' then 'récupère l''événement « '
           || coalesce((select e.title from public.rc_events e where e.id = (j ->> 'event_id')::bigint), '?') || ' »'
      when 'rc_mail_got'   then 'récupère le courrier « '
           || coalesce((select m.title from public.rc_mail m where m.id = (j ->> 'mail_id')::bigint), '?') || ' »'
      when 'rc_trophy_got' then 'trophée « ' || coalesce(j ->> 'kind', '?') || ' » '
           || case j ->> 'tier' when '1' then 'bronze' when '2' then 'argent' when '3' then 'or' else coalesce(j ->> 'tier', '') end
      when 'rc_rewards_got' then 'récupère la récompense ' || coalesce(j ->> 'code', '?')
      when 'rc_milestones'  then 'palier de collection ' || coalesce(j ->> 'sys', '?') || ' n°' || coalesce(j ->> 'step', '?')
    end;
    perform public.rc__act(new.device, 'reward', 2, t);
  exception when others then null;
  end;
  return new;
end $function$;

drop trigger if exists rc_act_events_got on public.rc_events_got;
create trigger rc_act_events_got after insert on public.rc_events_got
  for each row execute function public.rc__act_reward();
drop trigger if exists rc_act_mail_got on public.rc_mail_got;
create trigger rc_act_mail_got after insert on public.rc_mail_got
  for each row execute function public.rc__act_reward();
drop trigger if exists rc_act_trophy_got on public.rc_trophy_got;
create trigger rc_act_trophy_got after insert or update of tier on public.rc_trophy_got
  for each row execute function public.rc__act_reward();
drop trigger if exists rc_act_rewards_got on public.rc_rewards_got;
create trigger rc_act_rewards_got after insert on public.rc_rewards_got
  for each row execute function public.rc__act_reward();
drop trigger if exists rc_act_milestones on public.rc_milestones;
create trigger rc_act_milestones after insert on public.rc_milestones
  for each row execute function public.rc__act_reward();

-- ── Recyclage et fusion (libellé des lignes de pièces) ───────────────────────
-- (rc__bump et rc__tbump ne sont pas modifiés : on reconnaît l'action par le compteur de trophée)
create or replace function public.rc__act_tro()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare d int := coalesce(new.n, 0) - case when tg_op = 'UPDATE' then coalesce(old.n, 0) else 0 end;
begin
  begin
    if new.kind = 'recycle' then
      perform public.rc__act(new.device, 'recycle', 1, 'recycle ' || d || ' doublon(s)');
    elsif new.kind = 'fuse' then
      perform public.rc__act(new.device, 'fuse', 1, 'fusionne des cartes');
    end if;
  exception when others then null;
  end;
  return new;
end $function$;

drop trigger if exists rc_act_tro on public.rc_trophy_n;
create trigger rc_act_tro after insert or update of n on public.rc_trophy_n
  for each row when (new.kind in ('recycle', 'fuse')) execute function public.rc__act_tro();

-- ── Lecture admin ────────────────────────────────────────────────────────────
-- p_group : '' (tout), packs, bourse, trades, gifts, duels, rewards, coins, login
-- p_who   : bout de pseudo (vide = tous) ; p_before : id de la dernière ligne vue (0 = début)
create or replace function public.rc_admin_activity(p_device text, p_sig text, p_group text, p_who text, p_before bigint)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare kinds text[];
begin
  perform public.rc__admin(p_device, p_sig, 'act|' || coalesce(p_group, '') || '|' || coalesce(p_who, '') || '|' || coalesce(p_before, 0));
  kinds := case coalesce(p_group, '')
    when 'packs'   then array['pack', 'open', 'lot']
    when 'bourse'  then array['sell', 'buy', 'sold', 'unsell']
    when 'trades'  then array['trade_offer', 'trade_ok', 'trade_no']
    when 'gifts'   then array['gift', 'gift_in']
    when 'duels'   then array['duel']
    when 'rewards' then array['reward', 'week', 'wheel', 'quiz', 'gamedle']
    when 'coins'   then array['coins', 'recycle', 'fuse']
    when 'login'   then array['join', 'login']
    else null end;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'id', a.id, 'at', a.at, 'kind', a.kind, 'txt', a.txt, 'card', a.card, 'f', a.finish,
             'c', a.coins, 'p', a.pixels, 'dev', a.device,
             'name', (select p.name from public.rc_players p where p.device = a.device),
             'other', (select p.name from public.rc_players p where p.device = a.other)) order by a.id desc)
      from (select * from public.rc_activity x
             where (coalesce(p_before, 0) = 0 or x.id < p_before)
               and (kinds is null or x.kind = any(kinds))
               and (coalesce(p_who, '') = '' or x.device in
                     (select p.device from public.rc_players p where p.name ilike '%' || p_who || '%'))
             order by x.id desc limit 80) a), '[]'::jsonb);
end $function$;

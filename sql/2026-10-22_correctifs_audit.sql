-- ═══════════════════════════════════════════════════════════════════════════
-- Pixel Trade : correctifs de l'audit du 22/10/2026. Relançable, tout ou rien.
--  1. rc_mail_read : mêmes règles que rc_mail_list (courrier « à tous » seulement s'il est
--     plus récent que le compte et de moins de 30 jours ; groupes : moins de 30 jours).
--     Avant : un nouveau compte pouvait réclamer tous les anciens courriers par leur numéro.
--  5. rc_bs_invite : les Console Wars dépassées entre les deux joueurs (et les miennes) sont
--     réglées avant les contrôles → plus de « partie déjà en cours » pour une partie abandonnée.
--  6. Compte bloqué : plus de défi (lancer / accepter) ni d'inscription aux tournois ;
--     défier ou accepter contre un compte bloqué → « joueur indisponible ».
-- Lancement : psql -U postgres -d postgres -f 2026-10-22_correctifs_audit.sql
-- ═══════════════════════════════════════════════════════════════════════════
begin;

-- 6. message du blocage (affiché tel quel dans l'appli)
CREATE OR REPLACE FUNCTION public.rc__not_blocked(p_dev text)
 RETURNS void
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if exists (select 1 from public.rc_players where device = p_dev and blocked) then
    raise exception 'compte bloqué : échanges, ventes, achats, cadeaux, duels et tournois désactivés';
  end if;
end $function$;

-- 1. courrier
create or replace function public.rc_mail_read(p_device text, p_id bigint, p_sig text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare m public.rc_mail; v public.rc_players; i int; g jsonb := '{}'::jsonb;
begin
  perform public.rc__check(p_sig, p_device || '|mailread|' || p_id);
  select * into v from public.rc_players where device = p_device for update;
  if v.device is null then raise exception 'joueur inconnu'; end if;
  -- mêmes règles que rc_mail_list
  select * into m from public.rc_mail x where x.id = p_id
     and (x.device = p_device
          or (x.device is null and x.grp is null and x.created_at > v.created_at and x.created_at > now() - interval '30 days')
          or (x.grp is not null and x.created_at > now() - interval '30 days'
              and exists (select 1 from public.rc_mail_to t where t.mail_id = x.id and t.device = p_device)));
  if m.id is null then raise exception 'message inconnu'; end if;
  insert into public.rc_mail_got (device, mail_id) values (p_device, p_id) on conflict do nothing;
  if found then
    update public.rc_players set coins = coins + m.coins, pixels = pixels + m.pixels where device = p_device;
    for i in 1 .. least(m.packs, 10) loop
      insert into public.rc_gifts (receiver, giver, giver_name, kind) values (p_device, null, 'Pixel Trade', 'premium');
    end loop;
    g := public.rc__grant(p_device, m.reward);
  end if;
  select * into v from public.rc_players where device = p_device;
  return jsonb_build_object('coins', v.coins, 'pixels', v.pixels, 'gain', g);
end $function$;

-- 6. 4 en ligne : lancer un défi
CREATE OR REPLACE FUNCTION public.rc_c4_invite(p_device text, p_pid text, p_mode text, p_sig text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare v public.rc_players; o public.rc_players; gid bigint;
begin
  perform public.rc__check(p_sig, p_device || '|c4inv|' || coalesce(p_pid, '') || '|' || coalesce(p_mode, ''));
  if p_mode not in ('live', 'turn') then raise exception 'mode inconnu'; end if;
  select * into v from public.rc_players where device = p_device;
  select * into o from public.rc_players where pid = p_pid;
  if v.device is null or o.device is null then raise exception 'joueur inconnu'; end if;
  if o.device = v.device then raise exception 'pas contre toi-même'; end if;
  perform public.rc__not_blocked(p_device);
  if o.blocked then raise exception 'joueur indisponible'; end if;
  if p_mode = 'live' and coalesce(o.seen_at < now() - interval '2 minutes', true) then raise exception 'joueur hors ligne'; end if;
  if exists (select 1 from public.rc_c4 g where g.status in ('invite', 'playing') and g.mode = p_mode
              and ((g.p1 = v.device and g.p2 = o.device) or (g.p1 = o.device and g.p2 = v.device))
              and now() <= case when g.status = 'invite' then g.created_at + public.rc__c4_invite_limit(g.mode)
                                else g.move_at + public.rc__c4_limit(g.mode) end) then
    raise exception 'partie déjà en cours';
  end if;
  if (select count(*) from public.rc_c4 g where g.status in ('invite', 'playing') and v.device in (g.p1, g.p2)) >= 15 then
    raise exception 'trop de parties';
  end if;
  update public.rc_players set seen_at = now() where device = p_device;
  insert into public.rc_c4 (p1, p2, mode) values (v.device, o.device, p_mode) returning id into gid;
  return public.rc__c4_json((select g from public.rc_c4 g where g.id = gid), p_device);
end $function$;

-- 6. 4 en ligne : accepter (refuser reste possible)
CREATE OR REPLACE FUNCTION public.rc_c4_answer(p_device text, p_id bigint, p_accept boolean, p_sig text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare g public.rc_c4; c1 bigint; c2 bigint;
begin
  perform public.rc__check(p_sig, p_device || '|c4ans|' || p_id || '|' || case when p_accept then 1 else 0 end);
  perform public.rc__c4_settle(p_id);
  select * into g from public.rc_c4 where id = p_id for update;
  if g.id is null or p_device not in (g.p1, g.p2) then raise exception 'partie inconnue'; end if;
  if g.status <> 'invite' then raise exception 'invitation expirée'; end if;
  if not p_accept then
    update public.rc_c4 set status = 'done', reason = case when p_device = g.p1 then 'cancelled' else 'declined' end where id = p_id;
  else
    if p_device <> g.p2 then raise exception 'partie inconnue'; end if;
    perform public.rc__not_blocked(p_device);
    if exists (select 1 from public.rc_players where device = g.p1 and blocked) then raise exception 'joueur indisponible'; end if;
    -- mises : 50 pièces chacun, prélevées maintenant
    select coins into c1 from public.rc_players where device = g.p1 for update;
    select coins into c2 from public.rc_players where device = g.p2 for update;
    if c2 < g.stake then raise exception 'pas assez de pièces'; end if;
    if c1 < g.stake then raise exception 'adversaire sans pièces'; end if;
    update public.rc_players set coins = coins - g.stake where device in (g.p1, g.p2);
    update public.rc_players set seen_at = now() where device = p_device;
    update public.rc_c4 set status = 'playing', turn = 1, move_at = now() where id = p_id;
  end if;
  select * into g from public.rc_c4 where id = p_id;
  return public.rc__c4_json(g, p_device) || jsonb_build_object('coins', (select coins from public.rc_players where device = p_device));
end $function$;

-- 5 + 6. Console Wars : lancer un défi
CREATE OR REPLACE FUNCTION public.rc_bs_invite(p_device text, p_pid text, p_mode text, p_sig text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare v public.rc_players; o public.rc_players; gid bigint; x bigint;
begin
  perform public.rc__check(p_sig, p_device || '|bsinv|' || coalesce(p_pid, '') || '|' || coalesce(p_mode, ''));
  if p_mode not in ('live', 'turn') then raise exception 'mode inconnu'; end if;
  select * into v from public.rc_players where device = p_device;
  select * into o from public.rc_players where pid = p_pid;
  if v.device is null or o.device is null then raise exception 'joueur inconnu'; end if;
  if o.device = v.device then raise exception 'pas contre toi-même'; end if;
  perform public.rc__not_blocked(p_device);
  if o.blocked then raise exception 'joueur indisponible'; end if;
  if p_mode = 'live' and coalesce(o.seen_at < now() - interval '2 minutes', true) then raise exception 'joueur hors ligne'; end if;
  -- parties dépassées (abandonnées) : réglées d'abord, sinon elles bloqueraient les contrôles ci-dessous
  for x in select g.id from public.rc_bs g
            where g.status in ('invite', 'setup', 'playing') and v.device in (g.p1, g.p2)
              and now() > case when g.status = 'invite' then g.created_at + public.rc__bs_limit(g.mode, 'invite')
                               else g.move_at + public.rc__bs_limit(g.mode, g.status) end loop
    perform public.rc__bs_settle(x);
  end loop;
  if exists (select 1 from public.rc_bs g where g.status in ('invite', 'setup', 'playing') and g.mode = p_mode
              and ((g.p1 = v.device and g.p2 = o.device) or (g.p1 = o.device and g.p2 = v.device))) then
    raise exception 'partie déjà en cours';
  end if;
  if (select count(*) from public.rc_bs g where g.status in ('invite', 'setup', 'playing') and v.device in (g.p1, g.p2)) >= 15 then
    raise exception 'trop de parties';
  end if;
  update public.rc_players set seen_at = now() where device = p_device;
  insert into public.rc_bs (p1, p2, mode) values (v.device, o.device, p_mode) returning id into gid;
  return public.rc__bs_out(gid, p_device);
end $function$;

-- 6. Console Wars : accepter (refuser reste possible)
CREATE OR REPLACE FUNCTION public.rc_bs_answer(p_device text, p_id bigint, p_accept boolean, p_sig text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare g public.rc_bs; c1 bigint; c2 bigint;
begin
  perform public.rc__check(p_sig, p_device || '|bsans|' || p_id || '|' || case when p_accept then 1 else 0 end);
  perform public.rc__bs_settle(p_id);
  select * into g from public.rc_bs where id = p_id for update;
  if g.id is null or p_device not in (g.p1, g.p2) then raise exception 'partie inconnue'; end if;
  if g.status <> 'invite' then raise exception 'invitation expirée'; end if;
  if not p_accept then
    update public.rc_bs set status = 'done', reason = case when p_device = g.p1 then 'cancelled' else 'declined' end where id = p_id;
  else
    if p_device <> g.p2 then raise exception 'partie inconnue'; end if;
    perform public.rc__not_blocked(p_device);
    if exists (select 1 from public.rc_players where device = g.p1 and blocked) then raise exception 'joueur indisponible'; end if;
    select coins into c1 from public.rc_players where device = g.p1 for update;
    select coins into c2 from public.rc_players where device = g.p2 for update;
    if c2 < g.stake then raise exception 'pas assez de pièces'; end if;
    if c1 < g.stake then raise exception 'adversaire sans pièces'; end if;
    update public.rc_players set coins = coins - g.stake where device in (g.p1, g.p2);
    update public.rc_players set seen_at = now() where device = p_device;
    update public.rc_bs set status = 'setup', move_at = now() where id = p_id;
  end if;
  return public.rc__bs_out(p_id, p_device);
end $function$;

-- 6. Tournois : inscription
create or replace function public.rc_tour_join(p_device text, p_id bigint, p_sig text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare t public.rc_tour; c bigint;
begin
  perform public.rc__check(p_sig, p_device || '|tjoin|' || p_id);
  perform public.rc__not_blocked(p_device);
  select * into t from public.rc_tour where id = p_id for update;
  if t.id is null then raise exception 'tournoi inconnu'; end if;
  if t.status <> 'open' or now() >= t.start_at then raise exception 'inscriptions fermées'; end if;
  if exists (select 1 from public.rc_tour_players where tid = p_id and device = p_device) then raise exception 'déjà inscrit'; end if;
  if (select count(*) from public.rc_tour_players where tid = p_id) >= t.size then raise exception 'tournoi complet'; end if;
  select coins into c from public.rc_players where device = p_device for update;
  if c is null then raise exception 'joueur inconnu'; end if;
  if c < t.fee then raise exception 'pas assez de pièces'; end if;
  if t.fee > 0 then update public.rc_players set coins = coins - t.fee where device = p_device; end if;
  insert into public.rc_tour_players (tid, device, paid) values (p_id, p_device, t.fee);
  return public.rc__tour_json(p_id, p_device, true) || jsonb_build_object('coins', (select coins from public.rc_players where device = p_device));
end $function$;

commit;

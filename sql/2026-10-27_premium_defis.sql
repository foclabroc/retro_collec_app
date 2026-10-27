-- ═══════════════════════════════════════════════════════════════════════════
-- Pixel Trade : l'ouverture d'un paquet premium (acheté ou reçu en cadeau) et du paquet gratuit
-- compte enfin pour les défis de la semaine et le trophée Premium.
-- Cause : seul l'ancien rc_open appelait rc__wbump('premium' / 'free') ; rc_pick (le vrai chemin
-- depuis les 6 boosters) ne le faisait pas.
--  • rc_pending.gk : type réel du cadeau ouvert (premium, mixte…), gardé si la partie est reprise.
--  • rc_open_choice : renseigne gk.   • rc_pick : bump premium / gratuit (défis + trophées).
-- Les paquets déjà entamés avant ce fichier (gk vide) ne comptent pas.
-- Lancement : psql -U postgres -d postgres -f 2026-10-27_premium_defis.sql
-- ═══════════════════════════════════════════════════════════════════════════
begin;

alter table public.rc_pending add column if not exists gk text;

create or replace FUNCTION public.rc_open_choice(p_device text, p_kind text, p_sys text, p_sig text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  v public.rc_players;
  pd public.rc_pending;
  price int := public.rc__pack_price(p_kind);
  sp int := public.rc__special_cost(p_kind);
  packs jsonb := '[]'::jsonb; gid bigint; i int; gk text;
begin
  perform public.rc__check(p_sig, p_device || '|open6|' || coalesce(p_kind, '') || '|' || coalesce(p_sys, ''));
  select * into v from public.rc_players where device = p_device for update;
  if v.device is null then raise exception 'joueur inconnu'; end if;

  select * into pd from public.rc_pending where device = p_device;
  if pd.device is not null then
    return jsonb_build_object('choose', jsonb_array_length(pd.packs), 'kind', pd.kind, 'sys', pd.sys, 'resumed', true,
                              'coins', v.coins, 'lots', v.lots, 'pixels', v.pixels,
                              'gifts', (select count(*)::int from public.rc_gifts g where g.receiver = p_device and g.opened_at is null));
  end if;

  if price is null and sp is null then raise exception 'paquet inconnu'; end if;
  if p_kind in ('console', 'sconsole') and not exists (select 1 from public.rc_cards where sys = p_sys) then
    raise exception 'console inconnue';
  end if;
  if sp is not null then
    -- booster spécial : payé en pixels
    if v.pixels < sp then raise exception 'pas assez de pixels'; end if;
    update public.rc_players set pixels = pixels - sp where device = p_device;
  elsif p_kind = 'free' then
    if public.rc__free_in(p_device) > 0 then raise exception 'paquet gratuit pas encore prêt'; end if;
    update public.rc_players set last_free = public.rc__today(), last_free_at = now() where device = p_device;
  elsif p_kind = 'gift' then
    select g.id, g.kind into gid, gk from public.rc_gifts g
     where g.receiver = p_device and g.opened_at is null
       and (coalesce(p_sys, '') = '' or g.id::text = p_sys)
     order by g.id limit 1 for update;
    if gid is null then raise exception 'aucun cadeau'; end if;
    update public.rc_gifts set opened_at = now() where id = gid;
  elsif p_kind = 'lot' then
    if v.lots < 1 then raise exception 'aucun paquet du lot'; end if;
    update public.rc_players set lots = lots - 1 where device = p_device;
  elsif v.coins < price then
    raise exception 'pas assez de pièces';
  else
    update public.rc_players set coins = coins - price where device = p_device;
  end if;

  for i in 1..6 loop
    packs := packs || jsonb_build_array(public.rc__draw_pack(case when p_kind = 'gift' then coalesce(gk, 'gift') else p_kind end, p_sys, v.pity));
  end loop;
  insert into public.rc_pending (device, kind, sys, packs, gk) values (p_device, p_kind, p_sys, packs, gk);

  select * into v from public.rc_players where device = p_device;
  return jsonb_build_object('choose', 6, 'kind', p_kind, 'sys', p_sys, 'resumed', false,
                            'coins', v.coins, 'lots', v.lots, 'pixels', v.pixels,
                            'gifts', (select count(*)::int from public.rc_gifts g where g.receiver = p_device and g.opened_at is null));
end $function$;

create or replace function public.rc_pick(p_device text, p_choice integer, p_sig text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare
  v public.rc_players;
  pd public.rc_pending;
  kk text; e jsonb; c text; f int; r int; is_new boolean; got_epic boolean := false; nnew int := 0; s text;
  res jsonb := '[]'::jsonb; ev jsonb := '[]'::jsonb; miss jsonb; miss_b int;
begin
  perform public.rc__check(p_sig, p_device || '|pick|' || p_choice);
  select * into v from public.rc_players where device = p_device for update;
  if v.device is null then raise exception 'joueur inconnu'; end if;
  select * into pd from public.rc_pending where device = p_device for update;
  if pd.device is null then raise exception 'aucun booster à choisir'; end if;
  if p_choice is null or p_choice < 0 or p_choice >= jsonb_array_length(pd.packs) then
    raise exception 'booster inconnu';
  end if;

  for e in select * from jsonb_array_elements(pd.packs -> p_choice) loop
    c := e ->> 'c'; f := (e ->> 'f')::int; r := (e ->> 'r')::int;
    if r >= 3 then got_epic := true; end if;
    is_new := not exists (select 1 from public.rc_owned where device = p_device and card = c);
    if is_new then nnew := nnew + 1; end if;
    perform public.rc__give(p_device, c, f, 1);
    res := res || jsonb_build_object('c', c, 'f', f, 'r', r, 'n', is_new);
    select sys into s from public.rc_cards where id = c;
    perform public.rc__ev_bump(p_device, 'console', 1, s);  -- défi : cartes d'une console
  end loop;

  -- la meilleure carte des 5 autres boosters
  select x.card, (x.ord - 1)::int into miss, miss_b
    from (select p.ord, k.card from jsonb_array_elements(pd.packs) with ordinality p(pack, ord),
                 jsonb_array_elements(p.pack) k(card)) x
   where x.ord - 1 <> p_choice
   order by (x.card ->> 'r')::int * 3 + (x.card ->> 'f')::int desc, random()
   limit 1;
  if miss is not null then
    miss := miss || jsonb_build_object('b', miss_b,
      'n', not exists (select 1 from public.rc_owned where device = p_device and card = miss ->> 'c'));
  end if;

  delete from public.rc_pending where device = p_device;
  kk := case when pd.kind = 'gift' then pd.gk else pd.kind end;  -- type réel (un cadeau peut être un premium)
  insert into public.rc_pack_log (device, kind, sys) values (p_device, pd.kind, pd.sys);  -- stats admin
  update public.rc_players set packs = packs + 1, pity = case when got_epic then 0 else pity + 1 end,
         pixels = pixels + case when public.rc__special_cost(pd.kind) is null then 1 else 0 end
   where device = p_device;
  ev := ev || public.rc__bump(p_device, 'open', 1);
  if kk in ('free', 'premium') then perform public.rc__wbump(p_device, kk, 1); end if;  -- défis + trophée : paquet gratuit, premium
  if got_epic then  -- défi : carte épique ou mieux
    perform public.rc__wbump(p_device, 'epic', 1);
    perform public.rc__ev_bump(p_device, 'epics', 1);
  end if;
  perform public.rc__wbump(p_device, 'new', nnew);  -- défi : nouvelles cartes
  ev := ev || public.rc__milestones(p_device);
  perform public.rc__rescore(p_device);
  select * into v from public.rc_players where device = p_device;
  return jsonb_build_object('cards', res, 'choice', p_choice, 'missed', miss, 'kind', pd.kind, 'sys', pd.sys,
                            'coins', v.coins, 'pity', v.pity, 'pixels', v.pixels,
                            'pixel_gain', case when public.rc__special_cost(pd.kind) is null then 1 else 0 end, 'score', v.score, 'events', ev, 'lots', v.lots,
                            'gifts', (select count(*)::int from public.rc_gifts g where g.receiver = p_device and g.opened_at is null));
end $function$;

commit;

-- ═══════════════════════════════════════════════════════════════════════════
-- PIXEL TRADE — Bourse : achat groupé                               (relançable)
-- rc_market_buy_many : achète l'offre la moins chère de chaque carte choisie
-- (« card:finition:prix_max », 30 maximum). Une carte déjà vendue, devenue plus
-- chère ou trop chère pour le solde est passée, les autres sont achetées.
-- rc_market_buy (achat d'une seule offre) n'est pas modifiée.
-- ═══════════════════════════════════════════════════════════════════════════

-- Achat d'une offre, sans signature (appelé par rc_market_buy_many)
create or replace function public.rc__market_buy1(p_device text, p_id bigint)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare
  m public.rc_market; v public.rc_players; is_new boolean; ev jsonb := '[]'::jsonb;
begin
  select * into m from public.rc_market x where x.id = p_id and x.buyer is null for update skip locked;
  if m.id is null then return null; end if;
  if m.seller = p_device then raise exception 'c''est ton lot'; end if;
  perform public.rc__not_blocked(m.seller);
  select * into v from public.rc_players where device = p_device for update;
  if v.coins < m.price then raise exception 'pas assez de pièces'; end if;
  is_new := not exists (select 1 from public.rc_owned where device = p_device and card = m.card);
  update public.rc_market set buyer = p_device, sold_at = now() where id = m.id;
  update public.rc_players set coins = coins - m.price where device = p_device;
  update public.rc_players set coins = coins + m.price where device = m.seller;
  perform public.rc__give(p_device, m.card, m.finish, 1);
  ev := ev || public.rc__bump(p_device, 'trade', 1) || public.rc__milestones(p_device);
  perform public.rc__bump(m.seller, 'trade', 1);
  perform public.rc__ev_bump(m.seller, 'sales', 1);  -- défi : ventes en Bourse
  perform public.rc__wbump(m.seller, 'sale', 1);
  perform public.rc__tbump(p_device, 'buys', 1);  -- trophée : achats à la Bourse
  if is_new then perform public.rc__wbump(p_device, 'new', 1); end if;
  return jsonb_build_object('card', m.card, 'f', m.finish, 'n', is_new, 'price', m.price, 'events', ev);
end $function$;

-- p_items : « nes_001:0:120,snes_012:2:300 » (carte:finition:prix maximum accepté)
create or replace function public.rc_market_buy_many(p_device text, p_items text, p_sig text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare
  it text; parts text[]; v_card text; v_f int; v_max int; o record; r jsonb;
  got jsonb := '[]'::jsonb; skip jsonb := '[]'::jsonb; ev jsonb := '[]'::jsonb; n int := 0;
begin
  perform public.rc__check(p_sig, p_device || '|buymany|' || coalesce(p_items, ''));
  perform public.rc__not_blocked(p_device);
  foreach it in array array_remove(string_to_array(coalesce(p_items, ''), ','), '') loop
    n := n + 1;
    if n > 30 then exit; end if;
    parts := string_to_array(it, ':');
    v_card := parts[1];
    v_f := coalesce(nullif(parts[2], '')::int, 0);
    v_max := coalesce(nullif(parts[3], '')::int, 0);
    select x.id, x.price into o from public.rc_market x
     where x.card = v_card and x.finish = v_f and x.buyer is null and x.seller <> p_device
     order by x.price, x.created_at limit 1;
    if o.id is null then
      skip := skip || jsonb_build_object('card', v_card, 'f', v_f, 'why', 'sold');
    elsif o.price > v_max then
      skip := skip || jsonb_build_object('card', v_card, 'f', v_f, 'why', 'price', 'price', o.price);
    elsif (select coins from public.rc_players where device = p_device) < o.price then
      skip := skip || jsonb_build_object('card', v_card, 'f', v_f, 'why', 'coins');
    else
      begin
        r := public.rc__market_buy1(p_device, o.id);
        if r is null then
          skip := skip || jsonb_build_object('card', v_card, 'f', v_f, 'why', 'sold');
        else
          ev := ev || coalesce(r -> 'events', '[]'::jsonb);
          got := got || (r - 'events');
        end if;
      exception when others then
        skip := skip || jsonb_build_object('card', v_card, 'f', v_f, 'why', 'error', 'msg', sqlerrm);
      end;
    end if;
  end loop;
  if jsonb_array_length(got) > 0 then perform public.rc__rescore(p_device); end if;
  return jsonb_build_object('bought', got, 'skipped', skip, 'events', ev,
                            'coins', (select coins from public.rc_players where device = p_device));
end $function$;

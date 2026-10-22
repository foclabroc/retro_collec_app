-- ═══════════════════════════════════════════════════════════════════════════
-- Tournois, suite (22/10/2026) — relançable
--  · paquets des lots offerts au nom du tournoi (« Tournoi X · Étoile ») au lieu de « Pixel Trade »
--    (cadeaux reçus + journal d'activité) : réglage de transaction rc.gift_from lu par rc__grant
--  · rc__tour_me : fenêtre de félicitations (podium) jusqu'à 15 min après la fin
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function public.rc__grant(p_dev text, p_reward jsonb)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare
  r jsonb := public.rc__rw_clean(p_reward);
  k text; v text; n int; i int; c text; cards jsonb := '[]'::jsonb;
  lbl text;
begin
  -- rc.gift_from (réglage de la transaction) : nom du donneur des paquets offerts, « Pixel Trade » par défaut (tournois : « Tournoi X »)
  if r = '{}'::jsonb then return jsonb_build_object('cards', cards); end if;
  update public.rc_players
     set coins = coins + coalesce((r->>'coins')::int, 0),
         pixels = pixels + coalesce((r->>'pixels')::int, 0),
         lots = lots + 5 * coalesce((r->>'lots')::int, 0)
   where device = p_dev;
  for k, v in select key, value from jsonb_each_text(coalesce(r->'packs', '{}'::jsonb)) loop
    lbl := case k when 'mixte' then 'mixte' when 'premium' then 'premium' when 'mystery' then 'mystère'
                  when 'star' then 'Étoile' when 'gold' then 'Rétro d''or' end;
    for i in 1 .. v::int loop
      insert into public.rc_gifts (receiver, giver, giver_name, kind)
      values (p_dev, null, coalesce(nullif(current_setting('rc.gift_from', true), ''), 'Pixel Trade') || ' · ' || lbl, k);
    end loop;
  end loop;
  for k, v in select key, value from jsonb_each_text(coalesce(r->'cards', '{}'::jsonb)) loop
    for i in 1 .. v::int loop
      select id into c from public.rc_cards where rarity = k::int and saga is null order by random() limit 1;
      if c is not null then
        perform public.rc__give(p_dev, c, 0, 1);
        cards := cards || jsonb_build_object('c', c, 'r', k::int, 'f', 0);
      end if;
    end loop;
  end loop;
  if jsonb_array_length(cards) > 0 then perform public.rc__rescore(p_dev); end if;
  return r || jsonb_build_object('cards', cards);
end $function$;

-- « Coupe du samedi » → « Tournoi Coupe du samedi » ; « Tournoi de test » reste tel quel
create or replace function public.rc__tour_label(p_name text) returns text language sql immutable as $f$
  select case when p_name ilike 'tournoi%' then p_name else 'Tournoi ' || p_name end $f$;
alter function public.rc__tour_label(text) owner to rc_owner;

create or replace function public.rc__tour_finish(p_tid bigint)
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare t public.rc_tour; f public.rc_tour_matches; w text; s text; d text; a int;
begin
  select * into t from public.rc_tour where id = p_tid;
  select * into f from public.rc_tour_matches where tid = p_tid and round = t.rounds and slot = 0;
  w := f.winner;
  s := case when f.winner = f.p1 then f.p2 else f.p1 end;
  update public.rc_tour_players set place = 1 where tid = p_tid and device = w;
  if s is not null then update public.rc_tour_players set place = 2 where tid = p_tid and device = s; end if;
  -- lots fixes (paquets offerts au nom du tournoi dans les cadeaux et le journal)
  perform set_config('rc.gift_from', public.rc__tour_label(t.name), true);
  perform public.rc__grant(w, coalesce(t.lots->'1', '{}'::jsonb));
  if s is not null then perform public.rc__grant(s, coalesce(t.lots->'2', '{}'::jsonb)); end if;
  if t.rounds >= 2 then
    for d in select case when m.winner = m.p1 then m.p2 else m.p1 end
               from public.rc_tour_matches m where m.tid = p_tid and m.round = t.rounds - 1 loop
      if d is not null then
        update public.rc_tour_players set place = 3 where tid = p_tid and device = d;
        perform public.rc__grant(d, coalesce(t.lots->'3', '{}'::jsonb));
      end if;
    end loop;
  end if;
  perform set_config('rc.gift_from', '', true);
  -- cagnotte
  if t.pot > 0 then
    if t.split >= 100 or s is null then
      update public.rc_players set coins = coins + t.pot where device = w;
    else
      a := floor(t.pot * t.split / 100.0);
      update public.rc_players set coins = coins + a where device = w;
      update public.rc_players set coins = coins + (t.pot - a) where device = s;
    end if;
  end if;
  perform public.rc__tbump(w, 'tourney', 1);
  begin
    perform public.rc__feed_put(w, 'tour', s, null, null, t.game, t.pot, t.name);
  exception when others then null;
  end;
  update public.rc_tour set status = 'done', winner = w, second = s, ended_at = now() where id = p_tid;
end $function$;

create or replace function public.rc__tour_me(p_device text)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to 'public'
as $function$
declare r record; me int;
begin
  select m.*, t.name, t.game, t.rounds into r
    from public.rc_tour_matches m join public.rc_tour t on t.id = m.tid
   where t.status = 'running' and m.status in ('wait', 'play') and p_device in (m.p1, m.p2)
   order by m.id desc limit 1;
  if r.id is not null then
    me := case when r.p1 = p_device then 1 else 2 end;
    return jsonb_build_object(
      'tid', r.tid, 'name', r.name, 'game', r.game, 'mid', r.id, 'round', r.round, 'rounds', r.rounds, 'best', r.best,
      'status', r.status, 'gid', case when r.status = 'play' then r.game_id end,
      'ready', case when me = 1 then r.ready1 is not null else r.ready2 is not null end,
      'opp_ready', case when me = 1 then r.ready2 is not null else r.ready1 is not null end,
      'my_w', case when me = 1 then r.w1 else r.w2 end, 'opp_w', case when me = 1 then r.w2 else r.w1 end,
      'deadline', r.start_at + interval '3 minutes', 'now', now(),
      'opp', public.rc__pinfo(case when me = 1 then r.p2 else r.p1 end));
  end if;
  select t.id, t.name, t.game, t.start_at into r
    from public.rc_tour t join public.rc_tour_players tp on tp.tid = t.id and tp.device = p_device
   where t.status = 'open' and t.start_at <= now() + interval '10 minutes'
   order by t.start_at limit 1;
  if r.id is not null then
    return jsonb_build_object('tid', r.id, 'name', r.name, 'game', r.game, 'soon', r.start_at, 'now', now());
  end if;
  -- tournoi fini depuis moins de 15 min où je suis sur le podium : fenêtre de félicitations (une fois, côté appli)
  select t.id, t.name, t.game, tp.place, t.lots, t.pot, t.split, t.second into r
    from public.rc_tour t join public.rc_tour_players tp on tp.tid = t.id and tp.device = p_device
   where t.status = 'done' and t.ended_at > now() - interval '15 minutes' and tp.place is not null
   order by t.ended_at desc limit 1;
  if r.id is not null then
    return jsonb_build_object('tid', r.id, 'name', r.name, 'game', r.game, 'done', true, 'place', r.place,
      'reward', coalesce(r.lots -> (r.place::text), '{}'::jsonb),
      'pot', case when r.pot <= 0 then 0
                  when r.place = 1 then case when r.split >= 100 or r.second is null then r.pot else floor(r.pot * r.split / 100.0)::int end
                  when r.place = 2 and r.split < 100 then r.pot - floor(r.pot * r.split / 100.0)::int
                  else 0 end,
      'now', now());
  end if;
  return null;
end $function$;

alter function public.rc__grant(text, jsonb) owner to rc_owner;
alter function public.rc__tour_finish(bigint) owner to rc_owner;
alter function public.rc__tour_me(text) owner to rc_owner;
-- cadeaux et journal déjà écrits pour le tournoi de test (fait le 22/10, sans effet ensuite)
update public.rc_gifts g set giver_name = public.rc__tour_label(t.name) || substr(g.giver_name, length('Pixel Trade') + 1)
  from public.rc_tour t
 where t.status = 'done' and g.giver is null and g.giver_name like 'Pixel Trade · %'
   and g.created_at = t.ended_at;

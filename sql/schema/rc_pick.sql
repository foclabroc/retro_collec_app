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
    is_new := public.rc__is_new(p_device, c, f);
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

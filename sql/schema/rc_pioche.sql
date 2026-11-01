create or replace function public.rc_pioche_status(p_device text)
 returns boolean
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select coalesce((select p.pick_day is distinct from public.rc__today() from public.rc_players p where p.device = p_device), false) $function$;

create or replace function public.rc_pioche(p_device text, p_choice integer, p_sig text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare
  v public.rc_players;
  ids text[] := '{}'; res jsonb := '[]'::jsonb; ev jsonb := '[]'::jsonb;
  i int; r int; c text; f int; sy text; is_new boolean := false; got jsonb := null;
begin
  perform public.rc__check(p_sig, p_device || '|pioche|' || p_choice);
  if p_choice is null or p_choice not between 0 and 4 then raise exception 'choix invalide'; end if;
  select * into v from public.rc_players where device = p_device for update;
  if v.device is null then raise exception 'joueur inconnu'; end if;
  if v.pick_day is not distinct from public.rc__today() then raise exception 'déjà pioché aujourd''hui'; end if;
  -- 5 cartes différentes de tous types (consoles, toutes raretés, finitions) ; ni sagas ni Pokémon
  for i in 0 .. 4 loop
    r := public.rc__roll(0); c := null;
    select id into c from public.rc_cards where rarity = r and saga is null and id <> all(ids) order by random() limit 1;
    if c is null then
      select id, rarity into c, r from public.rc_cards where rarity <= r and saga is null and id <> all(ids) order by rarity desc, random() limit 1;
    end if;
    if c is null then raise exception 'catalogue vide'; end if;
    ids := ids || c;
    f := public.rc__roll_finish(r);
    res := res || jsonb_build_object('c', c, 'f', f, 'r', r);
  end loop;
  update public.rc_players set pick_day = public.rc__today() where device = p_device;
  -- seule la carte choisie est gagnée
  c := res -> p_choice ->> 'c'; f := (res -> p_choice ->> 'f')::int;
  is_new := public.rc__is_new(p_device, c, f);
  perform public.rc__give(p_device, c, f, 1);
  select sys into sy from public.rc_cards where id = c;
  perform public.rc__ev_bump(p_device, 'console', 1, sy);
  if is_new then perform public.rc__wbump(p_device, 'new', 1); end if;
  ev := ev || public.rc__milestones(p_device);
  perform public.rc__rescore(p_device);
  return jsonb_build_object('cards', res, 'pick', p_choice, 'n', is_new, 'events', ev);
end $function$;

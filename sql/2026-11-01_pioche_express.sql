-- Bonus : Pioche du jour (5 cartes face cachée, une choisie, toutes retournées) et Défi express du jour. Relançable.
alter table public.rc_players add column if not exists pick_day date;

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
  perform public.rc__tbump(p_device, 'pioche', 1);  -- trophée : pioches du jour
  ev := ev || public.rc__milestones(p_device);
  perform public.rc__rescore(p_device);
  return jsonb_build_object('cards', res, 'pick', p_choice, 'n', is_new, 'events', ev);
end $function$;

create table if not exists public.rc_express (
  device text not null,
  day date not null,
  kind text not null,
  goal integer not null,
  prog integer not null default 0,
  claimed boolean not null default false,
  primary key (device, day)
);
revoke all on table public.rc_express from anon, authenticated;
alter table public.rc_express owner to rc_owner;

-- mission du jour (la même pour tous), tirée dans une petite liste : kind, objectif, récompense
create or replace function public.rc__express_def(p_day date)
 returns table(kind text, goal integer, reward jsonb)
 language sql
 immutable
as $function$
  select m.kind, m.goal, m.reward from (values
    (0, 'open',    2, '{"coins":80}'::jsonb),
    (1, 'gift',    1, '{"coins":60}'::jsonb),
    (2, 'trade',   1, '{"coins":100}'::jsonb),
    (3, 'win',     1, '{"coins":100}'::jsonb),
    (4, 'gamedle', 1, '{"coins":60}'::jsonb),
    (5, 'play',    2, '{"coins":80}'::jsonb),
    (6, 'new',     2, '{"coins":80}'::jsonb),
    (7, 'quiz',    5, '{"coins":60}'::jsonb),
    (8, 'sale',    1, '{"coins":80}'::jsonb),
    (9, 'free',    1, '{"coins":50}'::jsonb),
    (10,'premium', 1, '{"coins":100}'::jsonb),
    (11,'epic',    1, '{"coins":150,"pixels":1}'::jsonb)
  ) m(i, kind, goal, reward) where m.i = abs(hashtext('express#' || p_day::text)) % 12 $function$;

-- avance la mission du jour (appelée par rc__wbump, jamais bloquante)
create or replace function public.rc__xbump(p_dev text, p_kind text, p_n integer)
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare d record;
begin
  begin
    select * into d from public.rc__express_def(public.rc__today());
    if d.kind is distinct from p_kind then return; end if;
    insert into public.rc_express (device, day, kind, goal, prog)
    values (p_dev, public.rc__today(), d.kind, d.goal, least(d.goal, p_n))
    on conflict (device, day) do update set prog = least(rc_express.goal, rc_express.prog + p_n)
      where not rc_express.claimed;
  exception when others then null;
  end;
end $function$;

create or replace function public.rc_express_get(p_device text)
 returns jsonb
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select jsonb_build_object('kind', d.kind, 'goal', d.goal, 'reward', d.reward,
                            'prog', coalesce(e.prog, 0), 'claimed', coalesce(e.claimed, false))
    from public.rc__express_def(public.rc__today()) d
    left join public.rc_express e on e.device = p_device and e.day = public.rc__today() $function$;

create or replace function public.rc_express_claim(p_device text, p_sig text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare e public.rc_express; d record; g jsonb; ev jsonb := '[]'::jsonb; v public.rc_players;
begin
  perform public.rc__check(p_sig, p_device || '|expclaim');
  perform 1 from public.rc_players where device = p_device for update;
  select * into d from public.rc__express_def(public.rc__today());
  select * into e from public.rc_express where device = p_device and day = public.rc__today() for update;
  if e.device is null or e.prog < d.goal then raise exception 'défi express pas fini'; end if;
  if e.claimed then raise exception 'déjà récupéré'; end if;
  update public.rc_express set claimed = true where device = e.device and day = e.day;
  g := public.rc__grant(p_device, d.reward);
  perform public.rc__tbump(p_device, 'express', 1);  -- trophée : défis express
  ev := ev || public.rc__milestones(p_device);
  select * into v from public.rc_players where device = p_device;
  return jsonb_build_object('reward', d.reward, 'coins', v.coins, 'pixels', v.pixels, 'events', ev);
end $function$;

create or replace function public.rc__wbump(p_dev text, p_kind text, p_n integer)
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare k text[];
begin
  if p_dev is null or coalesce(p_n, 0) <= 0 then return; end if;
  -- trophées : cadeaux, ventes, duels gagnés, Gamedle (comptés même hors des défis de la semaine)
  perform public.rc__tbump(p_dev, case p_kind when 'gift' then 'gifts' when 'sale' then 'sales' when 'win' then 'wins' when 'gamedle' then 'gamedle'
    when 'quiz' then 'quiz' when 'play' then 'played' when 'premium' then 'premium' end, p_n);
  perform public.rc__xbump(p_dev, p_kind, p_n);  -- défi express du jour
  k := public.rc__wkinds();
  if not (p_kind = any(k)) then return; end if;  -- pas au programme cette semaine
  perform public.rc__wk(p_dev);
  update public.rc_players set w_prog[array_position(k, p_kind)] =
         least(coalesce(w_prog[array_position(k, p_kind)], 0) + p_n, 9999)
   where device = p_dev;
end $function$;

-- progression du défi express envoyée en direct au joueur (événement « prog »)
create or replace trigger rc_express_rt after insert or update on public.rc_express
  for each row execute function public.rc__rt_me2();

alter function public.rc_pioche_status(text) owner to rc_owner;
alter function public.rc_pioche(text, integer, text) owner to rc_owner;
alter function public.rc__express_def(date) owner to rc_owner;
alter function public.rc__xbump(text, text, integer) owner to rc_owner;
alter function public.rc_express_get(text) owner to rc_owner;
alter function public.rc_express_claim(text, text) owner to rc_owner;
alter function public.rc__wbump(text, text, integer) owner to rc_owner;

notify pgrst, 'reload schema';

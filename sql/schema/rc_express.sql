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

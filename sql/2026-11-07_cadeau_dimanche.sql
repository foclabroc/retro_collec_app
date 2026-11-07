-- Cadeau du dimanche : 1 booster Pokemon + 1 Dessins animes + 1 Dragon Ball offerts chaque dimanche   (relancable)
-- A recuperer dans Paquets (rc_sunday_claim) : les 3 boosters arrivent dans les cadeaux recus,
-- nommes « Cadeau du dimanche · ... ». rc_notifs renvoie 'sunday' (pastille + notification Android).
alter table public.rc_players add column if not exists sunday_got date;

create or replace function public.rc__sunday()
 returns boolean language sql stable
as $function$ select extract(isodow from now() at time zone 'Europe/Paris') = 7 $function$;
alter function public.rc__sunday() owner to rc_owner;

create or replace function public.rc_sunday_claim(p_device text, p_sig text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare v public.rc_players;
begin
  perform public.rc__check(p_sig, p_device || '|sunday');
  select * into v from public.rc_players where device = p_device for update;
  if v.device is null then raise exception 'joueur inconnu'; end if;
  if not public.rc__sunday() then raise exception 'seulement le dimanche'; end if;
  if v.sunday_got is not distinct from public.rc__today() then raise exception 'deja recupere aujourd''hui'; end if;
  update public.rc_players set sunday_got = public.rc__today() where device = p_device;
  perform set_config('rc.gift_from', 'Cadeau du dimanche', true);
  perform public.rc__grant(p_device, '{"packs": {"pokemon": 1, "cartoon": 1, "dragonball": 1}}'::jsonb);
  perform set_config('rc.gift_from', '', true);
  return jsonb_build_object('ok', true,
    'gifts', (select count(*)::int from public.rc_gifts g where g.receiver = p_device and g.opened_at is null));
end $function$;
alter function public.rc_sunday_claim(text, text) owner to rc_owner;
grant execute on function public.rc_sunday_claim(text, text) to anon, authenticated;

-- rc_notifs : cadeau du dimanche disponible ?
do $$
declare d text; a text; b text;
begin
  d := pg_get_functiondef('public.rc_notifs(text)'::regprocedure);
  a := $x$    'lot_price', public.rc__lot_price(),$x$;
  b := $x$    'lot_price', public.rc__lot_price(),
    'sunday', (select public.rc__sunday() and sunday_got is distinct from public.rc__today() from public.rc_players where device = p_device),$x$;
  if position(b in d) > 0 then return; end if;
  if position(a in d) = 0 then raise exception 'texte introuvable dans rc_notifs'; end if;
  execute replace(d, a, b);
end $$;

notify pgrst, 'reload schema';

select public.rc__sunday() as dimanche, (public.rc_notifs((select device from public.rc_players limit 1)) ? 'sunday') as notifs_ok;

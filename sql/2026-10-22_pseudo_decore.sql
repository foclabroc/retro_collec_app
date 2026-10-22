-- 22/10/2026 : pseudo affiché personnalisable (emojis, symboles, 24 caractères) ; connexion et doublons
-- sur les lettres et chiffres seulement. « 🎮👾Foclabroc👾🕹️ » s'affiche, on se connecte avec « foclabroc »,
-- et personne d'autre ne peut prendre « ★Foclabroc★ ». Relançable.

-- 1) contrôle avant changement : deux joueurs qui auraient la même clé (lettres et chiffres) → arrêt, rien n'est modifié
do $$
declare c text;
begin
  select string_agg(k || ' (' || n || ')', ', ') into c from (
    select lower(regexp_replace(name, '[^[:alnum:]]', '', 'g')) k, string_agg(name, ' / ') n
      from public.rc_players group by 1 having count(*) > 1 or lower(regexp_replace(name, '[^[:alnum:]]', '', 'g')) = ''
  ) x;
  if c is not null then raise exception 'Pseudos en conflit, à renommer d''abord (admin) : %', c; end if;
end $$;

-- 2) clé du pseudo : lettres et chiffres seulement, en minuscules (accents gardés, emojis / symboles / espaces retirés)
create or replace function public.rc__name_key(p text)
 returns text
 language sql
 immutable
as $function$
  select lower(regexp_replace(coalesce(p, ''), '[^[:alnum:]]', '', 'g')) $function$;
alter function public.rc__name_key(text) owner to rc_owner;

update public.rc_players set name_key = public.rc__name_key(name) where name_key is distinct from public.rc__name_key(name);

-- 3) pseudo libre jusqu'à 24 caractères
create or replace function public.rc_set_profile(p_device text, p_name text, p_avatar integer, p_showcase text, p_sig text)
 returns text
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare
  v_name text := left(trim(coalesce(p_name, '')), 24);
  v_key  text := public.rc__name_key(left(trim(coalesce(p_name, '')), 24));
begin
  perform public.rc__check(p_sig, p_device || '|profile|' || coalesce(p_name, '') || '|' || p_avatar || '|' || coalesce(p_showcase, ''));
  if v_key = '' then raise exception 'pseudo vide'; end if;
  if exists (select 1 from public.rc_players where name_key = v_key and device <> p_device) then return 'taken'; end if;
  if (select count(*) from public.rc__items(p_showcase)) > 6 or not public.rc__has(p_device, p_showcase) then
    return 'showcase';
  end if;
  update public.rc_players set name = v_name, name_key = v_key, avatar = least(greatest(coalesce(p_avatar, 0), 0), 63),
         showcase = coalesce(p_showcase, ''), updated_at = now()
   where device = p_device;
  return 'ok';
end $function$;
alter function public.rc_set_profile(text, text, integer, text, text) owner to rc_owner;

create or replace function public.rc_name_free(p_name text)
 returns boolean
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select public.rc__name_key(left(trim(coalesce(p_name, '')), 24)) <> ''
     and not exists (select 1 from public.rc_players
                      where name_key = public.rc__name_key(left(trim(coalesce(p_name, '')), 24))) $function$;
alter function public.rc_name_free(text) owner to rc_owner;

create or replace function public.rc_admin_rename(p_device text, p_sig text, p_pid text, p_name text)
 returns text
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare
  v_name text := left(trim(coalesce(p_name, '')), 24);
  v_key  text := public.rc__name_key(left(trim(coalesce(p_name, '')), 24));
begin
  perform public.rc__admin(p_device, p_sig, 'rename|' || coalesce(p_pid, '') || '|' || coalesce(p_name, ''));
  if v_key = '' then raise exception 'pseudo vide'; end if;
  if exists (select 1 from public.rc_players where name_key = v_key and pid <> p_pid) then return 'taken'; end if;
  update public.rc_players set name = v_name, name_key = v_key, updated_at = now() where pid = p_pid;
  if not found then raise exception 'joueur inconnu'; end if;
  return 'ok';
end $function$;
alter function public.rc_admin_rename(text, text, text, text) owner to rc_owner;

-- 4) connexion : même clé, saisie jusqu'à 24 caractères
CREATE OR REPLACE FUNCTION public.rc_login(p_name text, p_hash text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare v public.rc_players;
begin
  select * into v from public.rc_players
   where name_key = public.rc__name_key(left(trim(coalesce(p_name, '')), 24)) for update;
  if v.device is null or v.pass_hash is null then raise exception 'identifiants incorrects'; end if;
  if v.pass_lock is not null and v.pass_lock > now() then raise exception 'trop de tentatives'; end if;
  if extensions.crypt(coalesce(p_hash, ''), v.pass_hash) <> v.pass_hash then
    update public.rc_players
       set pass_fail = case when pass_fail + 1 >= 5 then 0 else pass_fail + 1 end,
           pass_lock = case when pass_fail + 1 >= 5 then now() + interval '15 minutes' else pass_lock end
     where device = v.device;
    return null;  -- (pas d'exception : sinon le compteur d'erreurs serait annulé)
  end if;
  update public.rc_players set pass_fail = 0, pass_lock = null where device = v.device;
  return v.device;
end $function$;
alter function public.rc_login(text, text) owner to rc_owner;

-- 5) mentions @pseudo dans le chat (le '@' ne doit pas être retiré)
create or replace function public.rc_notifs(p_device text)
 returns jsonb
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select jsonb_build_object(
    'trades', (select count(*)::int from public.rc_trades t where t.receiver = p_device and t.status = 'pending'),
    'sales', coalesce((
      select jsonb_agg(jsonb_build_object('id', m.id, 'card', m.card, 'f', m.finish, 'price', m.price,
                                          'buyer', (select b.name from public.rc_players b where b.device = m.buyer))
                       order by m.sold_at)
        from public.rc_market m, public.rc_players me
       where me.device = p_device and m.seller = p_device and m.buyer is not null and m.sold_at > me.market_seen), '[]'::jsonb),
    'wheel', (select wheel_day is distinct from public.rc__today() from public.rc_players where device = p_device),
    'gifts', (select count(*)::int from public.rc_gifts g where g.receiver = p_device and g.opened_at is null),
    'gift_from', (select g.giver_name from public.rc_gifts g where g.receiver = p_device and g.opened_at is null order by g.id desc limit 1),
    'gift_last', (select coalesce(max(g.id), 0) from public.rc_gifts g where g.receiver = p_device),
    'gifts_left', (select 3 - case when gift_day = public.rc__today() then gift_n else 0 end from public.rc_players where device = p_device),
    'can_gift', (select gift_day is distinct from public.rc__today() or gift_n < 3 from public.rc_players where device = p_device),
    'week', coalesce(public.rc__wk_ready(p_device), 0),
    'trophies', coalesce(public.rc__tro_ready(p_device), 0),
    'reacts', coalesce(public.rc__reacts_new(p_device), 0),
    'lots', (select lots from public.rc_players where device = p_device),
    'free', public.rc__free_in(p_device) = 0,
    'free_in', public.rc__free_in(p_device),
    'free_at', (select coalesce(extract(epoch from last_free_at)::bigint, 0) from public.rc_players where device = p_device),
    'lot_free', (select public.rc__lot_day() and lot_free is distinct from public.rc__today() from public.rc_players where device = p_device),
    'lot_price', public.rc__lot_price(),
    'chat', (select count(*)::int from public.rc_chat c, public.rc_players me
              where me.device = p_device and c.id > me.chat_seen and c.device <> p_device and not c.hidden),
    'chat_last', (select coalesce(max(c.id), 0) from public.rc_chat c where not c.hidden),
    'mention', (select coalesce(max(c.id), 0) from public.rc_chat c, public.rc_players me
                 where me.device = p_device and c.id > me.chat_seen and c.device <> p_device and not c.hidden
                   and lower(regexp_replace(c.msg, '[^[:alnum:]@]', '', 'g')) like '%@' || me.name_key || '%')) $function$;
alter function public.rc_notifs(text) owner to rc_owner;

-- contrôle : 'foclabroc' et 'rémi69' attendus, puis plus aucun doublon
select public.rc__name_key('🎮👾Foclabroc👾🕹️') as k1, public.rc__name_key('Rémi_69') as k2,
       (select count(*) from (select name_key from public.rc_players group by 1 having count(*) > 1) x) as doublons;

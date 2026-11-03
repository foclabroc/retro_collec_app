create or replace function public.rc_admin_x(p_device text, p_sig text, p_op text, p_args text)
 returns jsonb language plpgsql security definer set search_path to 'public', 'extensions'
as $$
declare j jsonb; d text; v rc_players; n int; f int; c text; pw text; mode text;
begin
  perform public.rc__admin(p_device, p_sig, 'x|' || coalesce(p_op, '') || '|' || coalesce(p_args, ''));
  j := coalesce(nullif(p_args, ''), '{}')::jsonb;
  if p_op in ('player', 'balance', 'card', 'password', 'clearfail', 'note', 'mute') then
    select * into v from rc_players where pid = j->>'pid';
    if v.device is null then raise exception 'joueur inconnu'; end if;
    d := v.device;
  end if;
  -- journal : seulement les actions
  if p_op in ('balance', 'card', 'password', 'clearfail', 'note', 'mute') then
    insert into rc_admin_log (device, action)
    values (p_device, left('x|' || p_op || '|' || coalesce(v.name, '') || '|' || coalesce(p_args, ''), 400));
  end if;

  case p_op
  when 'dash' then return rc__adm_dash();
  when 'players' then return rc__adm_players();
  when 'player' then return rc__adm_player(j->>'pid');
  when 'econ' then return rc__adm_econ((j->>'days')::int);
  when 'catalog' then
    return coalesce((select jsonb_agg(jsonb_build_array(id, sys, rarity, title)) from rc_cards), '[]'::jsonb);

  when 'balance' then
    -- {pid, mode: add|set, coins, pixels, frag, why}
    mode := coalesce(j->>'mode', 'add');
    if mode = 'set' then
      update rc_players set coins = greatest(coalesce((j->>'coins')::bigint, coins), 0),
                            pixels = greatest(coalesce((j->>'pixels')::int, pixels), 0),
                            fragments = greatest(coalesce((j->>'frag')::int, fragments, 0), 0)
       where device = d;
    else
      update rc_players set coins = greatest(coins + coalesce((j->>'coins')::bigint, 0), 0),
                            pixels = greatest(pixels + coalesce((j->>'pixels')::int, 0), 0),
                            fragments = greatest(coalesce(fragments, 0) + coalesce((j->>'frag')::int, 0), 0)
       where device = d;
    end if;
    select * into v from rc_players where device = d;
    return jsonb_build_object('coins', v.coins, 'pixels', v.pixels, 'frag', v.fragments);

  when 'card' then
    -- {pid, card, f, n}  n > 0 : donner, n < 0 : retirer
    c := j->>'card'; f := coalesce((j->>'f')::int, 0); n := coalesce((j->>'n')::int, 1);
    if not exists (select 1 from rc_cards where id = c) then raise exception 'carte inconnue'; end if;
    if f not between 0 and 3 or n = 0 or abs(n) > 50 then raise exception 'valeurs invalides'; end if;
    if n > 0 then
      insert into rc_owned (device, card, finish, qty, first_at) values (d, c, f, n, now())
      on conflict (device, card, finish) do update set qty = rc_owned.qty + excluded.qty;
    else
      update rc_owned set qty = qty + n where device = d and card = c and finish = f and qty + n > 0;
      if not found then delete from rc_owned where device = d and card = c and finish = f; end if;
    end if;
    perform rc__rescore(d);
    return jsonb_build_object('qty', coalesce((select qty from rc_owned where device = d and card = c and finish = f), 0));

  when 'password' then
    -- nouveau mot de passe provisoire (8 caractères), renvoyé une seule fois
    pw := substr(translate(encode(gen_random_bytes(9), 'base64'), '+/=lIO0', 'xyzkmPQ'), 1, 8);
    update rc_players set pass_hash = crypt(encode(digest('pt-pass#41c9|' || pw, 'sha256'), 'hex'), gen_salt('bf', 8)),
                          pass_fail = 0, pass_lock = null
     where device = d;
    delete from rc_ip_log where kind = 'login_fail' and name = v.name_key;
    return jsonb_build_object('password', pw);

  when 'clearfail' then
    delete from rc_ip_log where kind = 'login_fail' and name = v.name_key;
    update rc_players set pass_fail = 0, pass_lock = null where device = d;
    return jsonb_build_object('ok', true);

  when 'note' then
    insert into rc_admin_notes (device, note, tags, at) values (d, left(coalesce(j->>'note', ''), 4000), left(coalesce(j->>'tags', ''), 400), now())
    on conflict (device) do update set note = excluded.note, tags = excluded.tags, at = now();
    return jsonb_build_object('ok', true);

  when 'mute' then
    -- {pid, hours}  0 = lever, -1 = définitif
    n := coalesce((j->>'hours')::int, 24);
    delete from rc_chat_bans where device = d;
    if n <> 0 then
      insert into rc_chat_bans (device, until) values (d, case when n < 0 then null else now() + make_interval(hours => n) end);
    end if;
    return jsonb_build_object('ok', true);

  else
    raise exception 'opération inconnue : %', p_op;
  end case;
end $$;

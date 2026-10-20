create or replace function public.rc_trophy_claim(p_device text, p_kind text, p_sig text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare x record; gain int; px int; v public.rc_players;
begin
  perform public.rc__check(p_sig, p_device || '|tclaim|' || p_kind);
  perform 1 from public.rc_players where device = p_device for update;
  if not found then raise exception 'joueur inconnu'; end if;
  select * into x from public.rc__tn(p_device) t where t.kind = p_kind;
  if x.kind is null then raise exception 'trophée inconnu'; end if;
  if x.got >= 3 then raise exception 'trophée complet'; end if;
  if x.n < x.t[x.got + 1] then raise exception 'palier pas atteint'; end if;
  gain := (array[100, 300, 800])[x.got + 1];
  px := (array[0, 0, 3])[x.got + 1];
  insert into public.rc_trophy_got (device, kind, tier) values (p_device, p_kind, x.got + 1)
  on conflict (device, kind) do update set tier = excluded.tier;
  update public.rc_players set coins = coins + gain, pixels = pixels + px where device = p_device
  returning * into v;
  return public.rc__tro_json(p_device) || jsonb_build_object('coins', v.coins, 'pixels', v.pixels, 'gain', gain, 'px', px, 'tier', x.got + 1);
end $function$;

CREATE OR REPLACE FUNCTION public.rc_claim(p_device text, p_sig text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare r record; ev jsonb := '[]'::jsonb;
begin
  perform public.rc__check(p_sig, p_device || '|claim');
  perform 1 from public.rc_players where device = p_device for update;
  if not found then return jsonb_build_object('events', ev); end if;
  for r in select * from public.rc_rewards w
            where (w.until is null or w.until >= public.rc__today())
              and not exists (select 1 from public.rc_rewards_got g where g.device = p_device and g.code = w.code)
  loop
    insert into public.rc_rewards_got (device, code) values (p_device, r.code) on conflict do nothing;
    if found then
      update public.rc_players set coins = coins + r.coins where device = p_device;
      ev := ev || jsonb_build_object('type', 'reward', 'code', r.code, 'coins', r.coins);
    end if;
  end loop;
  return jsonb_build_object('events', ev, 'coins', (select coins from public.rc_players where device = p_device));
end $function$

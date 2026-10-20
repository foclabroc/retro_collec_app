create or replace function public.rc_admin_card(p_device text, p_sig text, p_card text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
begin
  perform public.rc__admin(p_device, p_sig, 'card|' || coalesce(p_card, ''));
  return jsonb_build_object(
    'total', (select coalesce(sum(qty), 0) from public.rc_owned where card = p_card),
    'players', (select count(distinct device) from public.rc_owned where card = p_card and qty > 0),
    'finishes', coalesce((select jsonb_object_agg(f, n) from (select finish f, sum(qty)::int n from public.rc_owned
                                                                where card = p_card group by finish) x), '{}'::jsonb),
    'owners', coalesce((select jsonb_agg(jsonb_build_object('pid', p.pid, 'name', p.name, 'avatar', p.avatar, 'n', x.n, 'f', x.f) order by x.n desc)
                          from (select device, sum(qty)::int n, jsonb_object_agg(finish, qty) f from public.rc_owned
                                 where card = p_card and qty > 0 group by device order by sum(qty) desc limit 100) x
                          join public.rc_players p on p.device = x.device), '[]'::jsonb),
    'open', (select count(*) from public.rc_market where card = p_card and buyer is null),
    'sales', coalesce((select jsonb_agg(jsonb_build_object('price', m.price, 'f', m.finish, 'at', m.sold_at) order by m.sold_at desc)
                         from (select * from public.rc_market where card = p_card and buyer is not null order by sold_at desc limit 10) m), '[]'::jsonb));
end $function$;

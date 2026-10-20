create or replace function public.rc_admin_activity(p_device text, p_sig text, p_group text, p_who text, p_before bigint)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare kinds text[];
begin
  perform public.rc__admin(p_device, p_sig, 'act|' || coalesce(p_group, '') || '|' || coalesce(p_who, '') || '|' || coalesce(p_before, 0));
  kinds := case coalesce(p_group, '')
    when 'packs'   then array['pack', 'open', 'lot']
    when 'bourse'  then array['sell', 'buy', 'sold', 'unsell']
    when 'trades'  then array['trade_offer', 'trade_ok', 'trade_no']
    when 'gifts'   then array['gift', 'gift_in']
    when 'duels'   then array['duel']
    when 'rewards' then array['reward', 'week', 'wheel', 'quiz', 'gamedle']
    when 'coins'   then array['coins', 'recycle', 'fuse']
    when 'login'   then array['join', 'login']
    else null end;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'id', a.id, 'at', a.at, 'kind', a.kind, 'txt', a.txt, 'card', a.card, 'f', a.finish,
             'c', a.coins, 'p', a.pixels, 'dev', a.device,
             'name', (select p.name from public.rc_players p where p.device = a.device),
             'other', (select p.name from public.rc_players p where p.device = a.other)) order by a.id desc)
      from (select * from public.rc_activity x
             where (coalesce(p_before, 0) = 0 or x.id < p_before)
               and (kinds is null or x.kind = any(kinds))
               and (coalesce(p_who, '') = '' or x.device in
                     (select p.device from public.rc_players p where p.name ilike '%' || p_who || '%'))
             order by x.id desc limit 80) a), '[]'::jsonb);
end $function$;

create or replace function public.rc_stock_list(p_device text, p_sig text)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to 'public', 'extensions'
as $function$
begin
  perform public.rc__check(p_sig, p_device || '|stock');
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', s.id, 'c', s.card, 'f', s.finish, 'r', c.rarity, 'from', s.giver_name, 'at', s.created_at,
                                        'n', not exists (select 1 from public.rc_owned o where o.device = p_device and o.card = s.card))
                     order by s.id)
      from public.rc_card_stock s join public.rc_cards c on c.id = s.card
     where s.device = p_device and s.taken_at is null), '[]'::jsonb);
end $function$;

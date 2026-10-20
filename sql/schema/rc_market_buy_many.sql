create or replace function public.rc_market_buy_many(p_device text, p_items text, p_sig text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare
  it text; parts text[]; v_card text; v_f int; v_max int; o record; r jsonb;
  got jsonb := '[]'::jsonb; skip jsonb := '[]'::jsonb; ev jsonb := '[]'::jsonb; n int := 0;
begin
  perform public.rc__check(p_sig, p_device || '|buymany|' || coalesce(p_items, ''));
  perform public.rc__not_blocked(p_device);
  foreach it in array array_remove(string_to_array(coalesce(p_items, ''), ','), '') loop
    n := n + 1;
    if n > 30 then exit; end if;
    parts := string_to_array(it, ':');
    v_card := parts[1];
    v_f := coalesce(nullif(parts[2], '')::int, 0);
    v_max := coalesce(nullif(parts[3], '')::int, 0);
    select x.id, x.price into o from public.rc_market x
     where x.card = v_card and x.finish = v_f and x.buyer is null and x.seller <> p_device
     order by x.price, x.created_at limit 1;
    if o.id is null then
      skip := skip || jsonb_build_object('card', v_card, 'f', v_f, 'why', 'sold');
    elsif o.price > v_max then
      skip := skip || jsonb_build_object('card', v_card, 'f', v_f, 'why', 'price', 'price', o.price);
    elsif (select coins from public.rc_players where device = p_device) < o.price then
      skip := skip || jsonb_build_object('card', v_card, 'f', v_f, 'why', 'coins');
    else
      begin
        r := public.rc__market_buy1(p_device, o.id);
        if r is null then
          skip := skip || jsonb_build_object('card', v_card, 'f', v_f, 'why', 'sold');
        else
          ev := ev || coalesce(r -> 'events', '[]'::jsonb);
          got := got || (r - 'events');
        end if;
      exception when others then
        skip := skip || jsonb_build_object('card', v_card, 'f', v_f, 'why', 'error', 'msg', sqlerrm);
      end;
    end if;
  end loop;
  if jsonb_array_length(got) > 0 then perform public.rc__rescore(p_device); end if;
  return jsonb_build_object('bought', got, 'skipped', skip, 'events', ev,
                            'coins', (select coins from public.rc_players where device = p_device));
end $function$;

CREATE OR REPLACE FUNCTION public.rc_admin_market(p_device text, p_sig text, p_query text DEFAULT ''::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  perform public.rc__admin(p_device, p_sig, 'market|' || coalesce(p_query, ''));
  return coalesce((
    select jsonb_agg(x order by (x->>'ratio')::numeric desc nulls last, (x->>'price')::int desc) from (
      select jsonb_build_object('id', m.id, 'card', m.card, 'f', m.finish, 'price', m.price, 'at', m.created_at,
                                'avg', a.avg, 'ratio', case when a.avg > 0 then round(m.price::numeric / a.avg, 1) end,
                                'name', p.name, 'pid', p.pid, 'avatar', p.avatar) x
        from public.rc_market m join public.rc_players p on p.device = m.seller
        cross join lateral (select public.rc__avg_price(m.card, m.finish, m.id) as avg) a
       where m.buyer is null
         and (coalesce(p_query, '') = '' or p.name_key like public.rc__name_key(p_query) || '%')
       order by m.price desc limit 200) s), '[]'::jsonb);
end $function$

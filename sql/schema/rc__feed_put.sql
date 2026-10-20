CREATE OR REPLACE FUNCTION public.rc__feed_put(p_dev text, p_kind text, p_other text, p_card text, p_f integer, p_sys text, p_n integer, p_extra text, p_dedup boolean DEFAULT false)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_id bigint;
begin
  if p_dev is null then return; end if;
  if p_dedup and exists (select 1 from public.rc_feed
              where device = p_dev and kind = p_kind and other is not distinct from p_other
                and card is not distinct from p_card and sys is not distinct from p_sys
                and at > now() - interval '10 minutes') then
    return;
  end if;
  insert into public.rc_feed (device, kind, other, card, finish, sys, n, extra)
  values (p_dev, p_kind, p_other, p_card, p_f, p_sys, p_n, p_extra)
  returning id into v_id;
  if v_id % 50 = 0 then delete from public.rc_feed where id < v_id - 800; end if;  -- garde ~800 nouvelles
end $function$

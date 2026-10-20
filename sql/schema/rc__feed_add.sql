CREATE OR REPLACE FUNCTION public.rc__feed_add(p_dev text, p_kind text, p_card text, p_f integer, p_sys text, p_n integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_id bigint;
begin
  -- pas deux fois la même nouvelle en 10 minutes (achat + revente, échanges…)
  if exists (select 1 from public.rc_feed
              where device = p_dev and kind = p_kind and card is not distinct from p_card
                and sys is not distinct from p_sys and at > now() - interval '10 minutes') then
    return;
  end if;
  insert into public.rc_feed (device, kind, card, finish, sys, n) values (p_dev, p_kind, p_card, p_f, p_sys, p_n)
  returning id into v_id;
  if v_id % 50 = 0 then delete from public.rc_feed where id < v_id - 500; end if;  -- garde ~500 nouvelles
end $function$

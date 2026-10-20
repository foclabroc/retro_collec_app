create or replace function public.rc__act(p_dev text, p_kind text, p_prio int, p_txt text,
                                          p_card text default null, p_f int default null, p_other text default null,
                                          p_dc int default 0, p_dp int default 0)
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare r record; v_id bigint;
begin
  if p_dev is null then return; end if;
  select id, prio into r from public.rc_activity
   where tx = txid_current() and device = p_dev order by id desc limit 1;
  if found and (r.prio < 2 or p_prio < 2) then  -- deux actions connues restent sur deux lignes
    update public.rc_activity
       set coins = coins + coalesce(p_dc, 0), pixels = pixels + coalesce(p_dp, 0),
           kind  = case when p_prio > r.prio then p_kind  else kind  end,
           txt   = case when p_prio > r.prio then p_txt   else txt   end,
           card  = case when p_prio > r.prio then p_card  else card  end,
           finish= case when p_prio > r.prio then p_f     else finish end,
           other = case when p_prio > r.prio then p_other else other end,
           prio  = greatest(prio, p_prio)
     where id = r.id;
  else
    insert into public.rc_activity (device, kind, prio, txt, card, finish, other, coins, pixels)
    values (p_dev, p_kind, p_prio, coalesce(p_txt, ''), p_card, p_f, p_other, coalesce(p_dc, 0), coalesce(p_dp, 0))
    returning id into v_id;
    if v_id % 500 = 0 then delete from public.rc_activity where at < now() - interval '30 days'; end if;
  end if;
exception when others then null;  -- le journal ne doit jamais bloquer le jeu
end $function$;

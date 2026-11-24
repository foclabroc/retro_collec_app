CREATE OR REPLACE FUNCTION public.rc__milestones(p_dev text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
declare
  rec record; s int; ev jsonb := '[]'::jsonb; reward int;
begin
  for rec in
    select c.sys, count(*) as total, count(o.card) as mine, max(so.n) as old_n, bool_and(c.saga is null) as console,
           count(pl.card) as plat
      from public.rc_cards c
      left join (select distinct card from public.rc_owned where device = p_dev and qty > 0 and finish < 3) o on o.card = c.id  -- full art : onglet a part
      left join (select distinct card from public.rc_owned where device = p_dev and qty > 0 and finish = 4) pl on pl.card = c.id
      left join public.rc_sys_old so on so.sys = c.sys
     group by c.sys
  loop
    -- ancienne serie complete (console agrandie le 15/11) : 2000 pieces une fois, palier 99
    if rec.old_n is not null and rec.old_n < rec.total and rec.mine >= rec.old_n then
      insert into public.rc_milestones (device, sys, step) values (p_dev, rec.sys, 99) on conflict do nothing;
      if found then
        update public.rc_players set coins = coins + 2000 where device = p_dev;
        ev := ev || jsonb_build_object('type', 'milestone', 'sys', rec.sys, 'step', round(rec.old_n * 100.0 / rec.total)::int,
                                       'coins', 2000, 'old', rec.old_n);
      end if;
    end if;
    foreach s in array case when rec.sys like 'sg\_%' then array[50, 100] else array[25, 50, 75, 100] end loop
      if rec.mine * 100 >= rec.total * s then
        insert into public.rc_milestones (device, sys, step) values (p_dev, rec.sys, s) on conflict do nothing;
        if found then
          if rec.sys like 'sg\_%' then
            reward := case s when 50 then 100 else 500 end;
            update public.rc_players set coins = coins + reward, pixels = pixels + case when s = 100 then 2 else 0 end where device = p_dev;
          else
            reward := case s when 25 then 100 when 50 then 250 when 75 then 500 else 2000 end;
            update public.rc_players set coins = coins + reward where device = p_dev;
          end if;
          ev := ev || (jsonb_build_object('type', 'milestone', 'sys', rec.sys, 'step', s, 'coins', reward)
                       || case when s = 100 and rec.console then jsonb_build_object('platine', true) else '{}'::jsonb end);
        end if;
      end if;
    end loop;
    -- serie Platine finie : 5 000 pieces une fois (palier 200)
    if rec.console and rec.plat >= rec.total
       and exists (select 1 from public.rc_milestones m where m.device = p_dev and m.sys = rec.sys and m.step = 100) then
      insert into public.rc_milestones (device, sys, step) values (p_dev, rec.sys, 200) on conflict do nothing;
      if found then
        update public.rc_players set coins = coins + 5000 where device = p_dev;
        ev := ev || jsonb_build_object('type', 'platine_done', 'sys', rec.sys, 'coins', 5000);
      end if;
    end if;
  end loop;
  return ev;
end $function$;

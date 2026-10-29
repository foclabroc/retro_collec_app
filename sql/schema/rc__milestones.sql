CREATE OR REPLACE FUNCTION public.rc__milestones(p_dev text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
declare
  rec record; s int; ev jsonb := '[]'::jsonb; reward int;
begin
  for rec in
    select c.sys, count(*) as total, count(o.card) as mine
      from public.rc_cards c
      left join (select distinct card from public.rc_owned where device = p_dev and qty > 0 and finish <> 3) o on o.card = c.id  -- full art : onglet à part
     group by c.sys
  loop
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
          ev := ev || jsonb_build_object('type', 'milestone', 'sys', rec.sys, 'step', s, 'coins', reward);
        end if;
      end if;
    end loop;
  end loop;
  return ev;
end $function$

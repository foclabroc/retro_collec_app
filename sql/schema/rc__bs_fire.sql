CREATE OR REPLACE FUNCTION public.rc__bs_fire(p_id bigint, p_side integer, p_cell integer, p_at timestamp with time zone)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare g public.rc_bs; f jsonb; shots text; hit boolean;
begin
  select * into g from public.rc_bs where id = p_id;
  f := case when p_side = 1 then g.fleet2 else g.fleet1 end;
  shots := case when p_side = 1 then g.shots1 else g.shots2 end;
  hit := exists (select 1 from jsonb_array_elements(f) s where p_cell = any(public.rc__bs_ship_cells(s)));
  shots := overlay(shots placing case when hit then 'h' else 'm' end from p_cell + 1 for 1);
  if p_side = 1 then update public.rc_bs set shots1 = shots where id = p_id;
  else update public.rc_bs set shots2 = shots where id = p_id; end if;
  update public.rc_bs set moves = moves + 1, last_cell = p_cell, last_by = p_side,
                          turn = case when hit then p_side else 3 - p_side end, move_at = p_at
   where id = p_id;
  if length(replace(replace(shots, '0', ''), 'm', '')) >= 17 then
    perform public.rc__bs_finish(p_id, p_side, 'win');
  end if;
end $function$

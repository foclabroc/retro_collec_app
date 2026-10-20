CREATE OR REPLACE FUNCTION public.rc__c4_win(p_board text, p_r integer, p_c integer, p_s text)
 RETURNS boolean
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
declare dr int[] := array[0, 1, 1, 1]; dc int[] := array[1, 0, 1, -1]; k int; n int; rr int; cc int; sgn int;
begin
  for k in 1..4 loop
    n := 1;
    foreach sgn in array array[1, -1] loop
      rr := p_r + dr[k] * sgn; cc := p_c + dc[k] * sgn;
      while rr between 0 and 5 and cc between 0 and 6 and substr(p_board, rr * 7 + cc + 1, 1) = p_s loop
        n := n + 1; rr := rr + dr[k] * sgn; cc := cc + dc[k] * sgn;
      end loop;
    end loop;
    if n >= 4 then return true; end if;
  end loop;
  return false;
end $function$

CREATE OR REPLACE FUNCTION public.rc__bs_valid(f jsonb)
 RETURNS boolean
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
declare s jsonb; seen text[] := '{}'; used int[] := '{}'; r int; c int; n int; h boolean; cells int[];
begin
  if f is null or jsonb_typeof(f) <> 'array' or jsonb_array_length(f) <> 5 then return false; end if;
  for s in select value from jsonb_array_elements(f) loop
    n := public.rc__bs_len(s->>'k');
    if n is null or (s->>'k') = any(seen) then return false; end if;
    seen := seen || (s->>'k');
    r := (s->>'r')::int; c := (s->>'c')::int; h := (s->>'h')::boolean;
    if r is null or c is null or h is null or r < 0 or c < 0 then return false; end if;
    if (h and (r > 7 or c + n > 8)) or (not h and (c > 7 or r + n > 8)) then return false; end if;
    cells := public.rc__bs_ship_cells(s);
    if used && cells then return false; end if;
    used := used || cells;
  end loop;
  return true;
end $function$

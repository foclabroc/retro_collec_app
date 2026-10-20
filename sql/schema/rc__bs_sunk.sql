CREATE OR REPLACE FUNCTION public.rc__bs_sunk(f jsonb, shots text)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select coalesce(jsonb_agg(s), '[]'::jsonb) from jsonb_array_elements(coalesce(f, '[]'::jsonb)) s
   where not exists (select 1 from unnest(public.rc__bs_ship_cells(s)) x where substr(shots, x + 1, 1) <> 'h') $function$

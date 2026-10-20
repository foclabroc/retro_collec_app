CREATE OR REPLACE FUNCTION public.rc__bs_ship_cells(s jsonb)
 RETURNS integer[]
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select array_agg(case when (s->>'h')::boolean then (s->>'r')::int * 8 + (s->>'c')::int + i
                        else ((s->>'r')::int + i) * 8 + (s->>'c')::int end order by i)
    from generate_series(0, public.rc__bs_len(s->>'k') - 1) i $function$

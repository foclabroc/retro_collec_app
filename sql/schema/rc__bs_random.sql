CREATE OR REPLACE FUNCTION public.rc__bs_random()
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
declare f jsonb; k text; s jsonb; used int[]; tries int; ok boolean;
begin
  loop
    f := '[]'::jsonb; used := '{}'; ok := true;
    foreach k in array array['neo', 'ps', 'md', 'nes', 'gb'] loop
      tries := 0;
      loop
        tries := tries + 1;
        s := jsonb_build_object('k', k, 'r', floor(random() * 8)::int, 'c', floor(random() * 8)::int, 'h', random() < 0.5);
        if ((s->>'h')::boolean and (s->>'c')::int + public.rc__bs_len(k) <= 8)
           or (not (s->>'h')::boolean and (s->>'r')::int + public.rc__bs_len(k) <= 8) then
          if not (used && public.rc__bs_ship_cells(s)) then exit; end if;
        end if;
        if tries > 200 then ok := false; exit; end if;
      end loop;
      if not ok then exit; end if;
      used := used || public.rc__bs_ship_cells(s);
      f := f || jsonb_build_array(s);
    end loop;
    if ok then return f; end if;
  end loop;
end $function$

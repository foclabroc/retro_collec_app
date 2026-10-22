create or replace function public.rc__tour_label(p_name text) returns text language sql immutable as $f$
  select case when p_name ilike 'tournoi%' then p_name else 'Tournoi ' || p_name end $f$;

-- =================================================================
-- PIXEL TRADE - cadeau du dimanche : + 1 booster Coupe du monde (relancable, 100 % ASCII)
-- rc_sunday_claim : pokemon + cartoon + dragonball  ->  + football
-- =================================================================
do $$
declare d text; fn regprocedure := 'public.rc_sunday_claim(text,text)'::regprocedure;
  a text := '{"packs": {"pokemon": 1, "cartoon": 1, "dragonball": 1}}';
  b text := '{"packs": {"pokemon": 1, "cartoon": 1, "dragonball": 1, "football": 1}}';
begin
  d := pg_get_functiondef(fn);
  if position(b in d) > 0 then raise notice 'deja fait'; return; end if;
  if position(a in d) = 0 then raise exception 'texte introuvable dans rc_sunday_claim : rien change'; end if;
  execute replace(d, a, b);
end $$;
alter function public.rc_sunday_claim(text,text) owner to rc_owner;

notify pgrst, 'reload schema';

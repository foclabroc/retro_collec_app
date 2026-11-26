-- =================================================================
-- PIXEL TRADE - prime des bornes : retour aux anciennes regles (relancable, 100 % ASCII)
-- Annule sql/2026-11-25_borne_prime.sql : +20 pieces des qu'on bat le record de la semaine
-- d'une borne (une fois par jour et par borne, pas sur la sienne), sans limite de bornes par jour.
-- =================================================================
do $$
declare d text; fn regprocedure := 'public.rc_cab_end(text,bigint,integer,text)'::regprocedure;
  a1 text := 'v_new boolean := false; v_prevdev text;';
  b1 text := 'v_new boolean := false;';
  a2 text := 'select r.score, r.device into v_prev, v_prevdev from public.rc__cab_rec(o.device, x.game) r;';
  b2 text := 'select r.score into v_prev from public.rc__cab_rec(o.device, x.game) r;';
  a3 text := 'if v_new and o.device <> p_device and not me.blocked
       and v_prevdev is not null and v_prevdev <> p_device  -- record d''un autre joueur seulement
       and (select count(*) from public.rc_cab_paid cp where cp.device = p_device and cp.day = public.rc__today())
           < public.rc__cfg(''cab_prime_max'', 10) then';
  b3 text := 'if v_new and o.device <> p_device and not me.blocked then';
begin
  d := pg_get_functiondef(fn);
  if position('v_prevdev' in d) = 0 then raise notice 'deja fait'; return; end if;
  if position(a1 in d) = 0 or position(a2 in d) = 0 or position(a3 in d) = 0 then
    raise exception 'texte introuvable dans rc_cab_end : rien change';
  end if;
  execute replace(replace(replace(d, a1, b1), a2, b2), a3, b3);
end $$;
alter function public.rc_cab_end(text,bigint,integer,text) owner to rc_owner;

notify pgrst, 'reload schema';

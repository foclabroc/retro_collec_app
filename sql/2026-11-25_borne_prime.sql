-- =================================================================
-- PIXEL TRADE - prime des bornes resserree (relancable, 100 % ASCII)
-- Avant : +20 pieces des qu'on battait le record de la semaine d'une borne, meme vide ou le sien
--   (un joueur : ~85 bornes payees par jour, 50 000 pieces en un mois).
-- Maintenant, dans rc_cab_end :
--   1) prime seulement si le record battu appartenait a UN AUTRE joueur (pas de record vide, pas le sien) ;
--   2) au plus 10 bornes payees par jour et par joueur (reglage 'cab_prime_max' de rc_config.live).
-- Le record, le classement de la borne et le message au proprietaire ne changent pas.
-- =================================================================
do $$
declare d text; fn regprocedure := 'public.rc_cab_end(text,bigint,integer,text)'::regprocedure; n int := 0;
  a1 text := 'v_new boolean := false;';
  b1 text := 'v_new boolean := false; v_prevdev text;';
  a2 text := 'select r.score into v_prev from public.rc__cab_rec(o.device, x.game) r;';
  b2 text := 'select r.score, r.device into v_prev, v_prevdev from public.rc__cab_rec(o.device, x.game) r;';
  a3 text := 'if v_new and o.device <> p_device and not me.blocked then';
  b3 text := 'if v_new and o.device <> p_device and not me.blocked
       and v_prevdev is not null and v_prevdev <> p_device  -- record d''un autre joueur seulement
       and (select count(*) from public.rc_cab_paid cp where cp.device = p_device and cp.day = public.rc__today())
           < public.rc__cfg(''cab_prime_max'', 10) then';
begin
  d := pg_get_functiondef(fn);
  if position('v_prevdev' in d) > 0 then raise notice 'deja fait'; return; end if;
  if position(a1 in d) = 0 or position(a2 in d) = 0 or position(a3 in d) = 0 then
    raise exception 'texte introuvable dans rc_cab_end : rien change';
  end if;
  d := replace(replace(replace(d, a1, b1), a2, b2), a3, b3);
  execute d;
end $$;
alter function public.rc_cab_end(text,bigint,integer,text) owner to rc_owner;

notify pgrst, 'reload schema';

select position('v_prevdev' in pg_get_functiondef('public.rc_cab_end(text,bigint,integer,text)'::regprocedure)) > 0 as ok;

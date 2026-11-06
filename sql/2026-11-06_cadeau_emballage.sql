-- Cadeau : renvoyer aussi le vrai type du paquet offert (gk), pour afficher le bon emballage   (relançable)
-- (booster Dragon Ball / Pokemon / Dessins animes offert : l'appli montrait l'emballage standard)
do $$
declare d text; rec record;
begin
  for rec in
    select * from (values
      ('public.rc_open_choice(text,text,text,text)',
       $a$'kind', pd.kind, 'sys', pd.sys, 'resumed', true,$a$,
       $b$'kind', pd.kind, 'sys', pd.sys, 'gk', pd.gk, 'resumed', true,$b$),
      ('public.rc_open_choice(text,text,text,text)',
       $a$'kind', p_kind, 'sys', p_sys, 'resumed', false,$a$,
       $b$'kind', p_kind, 'sys', p_sys, 'gk', gk, 'resumed', false,$b$),
      ('public.rc_pick(text,integer,text)',
       $a$'missed', miss, 'kind', pd.kind, 'sys', pd.sys,$a$,
       $b$'missed', miss, 'kind', pd.kind, 'sys', pd.sys, 'gk', pd.gk,$b$),
      ('public.rc_pending_get(text,text)',
       $a$'kind', pd.kind, 'sys', pd.sys, 'resumed', true)$a$,
       $b$'kind', pd.kind, 'sys', pd.sys, 'gk', pd.gk, 'resumed', true)$b$)
    ) as x(fn, a, b)
  loop
    if to_regprocedure(rec.fn) is null then raise exception 'fonction absente : %', rec.fn; end if;
    d := pg_get_functiondef(to_regprocedure(rec.fn));
    if position(rec.b in d) > 0 then continue; end if;
    if position(rec.a in d) = 0 then raise exception 'texte introuvable dans % : %', rec.fn, left(rec.a, 50); end if;
    execute replace(d, rec.a, rec.b);
  end loop;
end $$;

notify pgrst, 'reload schema';

select 'ok' as cadeau_emballage;

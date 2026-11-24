-- 24/11/2026 : outil admin web, finition Platine (4).
-- rc_admin_x : 'card' (donner / retirer) et 'card_gift' (offrir) acceptent la finition 4 ;
-- une Platine offerte exige que la console du joueur soit debloquee (sinon il ne pourrait pas la ranger).
-- Retouche sur place (remplacements verifies, comme le 06/11). Relancable. 100 % ASCII.
do $$
declare rec record; d text;
begin
  for rec in
    select * from (values
      ('public.rc_admin_x(text,text,text,text)',
       $a$if f not between 0 and 3 or n = 0 or abs(n) > 50 then raise exception 'valeurs invalides'; end if;$a$,
       $b$if f not between 0 and 4 or n = 0 or abs(n) > 50 then raise exception 'valeurs invalides'; end if;$b$),
      ('public.rc_admin_x(text,text,text,text)',
       $a$if f not between 0 and 3 or n not between 1 and 20 then raise exception 'valeurs invalides'; end if;$a$,
       $b$if f not between 0 and 4 or n not between 1 and 20 then raise exception 'valeurs invalides'; end if;
    if f = 4 and not public.rc__platine_ok(d, c) then raise exception 'platine verrouillee'; end if;$b$)
    ) as x(fn, a, b)
  loop
    if to_regprocedure(rec.fn) is null then
      raise notice 'fonction absente (ignoree) : %', rec.fn;
      continue;
    end if;
    d := pg_get_functiondef(to_regprocedure(rec.fn));
    if position(rec.b in d) > 0 then
      raise notice 'deja fait : %', left(rec.b, 50);
      continue;
    elsif position(rec.a in d) = 0 then
      raise notice 'texte introuvable dans % : %', rec.fn, left(rec.a, 60);
      continue;
    end if;
    execute replace(d, rec.a, rec.b);
    raise notice 'remplace : %', left(rec.b, 50);
  end loop;
end $$;

notify pgrst, 'reload schema';

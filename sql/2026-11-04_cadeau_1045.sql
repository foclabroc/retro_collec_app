-- La 1.0.45 donne le cadeau de la 1.0.44 à ceux qui ne l'ont pas eu (une seule fois en tout)   (relançable)
-- Lancé par Claude via l'outil SQL le 4/11.
do $$
declare d text;
begin
  d := pg_get_functiondef('public.rc_upgrade_gift'::regproc);
  if position($b$v_ver = '1.0.45' then v_ver := '1.0.44'$b$ in d) > 0 then return; end if;
  if position($a$  if v_ver in ('1.0.24', '1.0.25', '1.0.26', '1.0.27') then v_ver := '1.0.23'; end if;$a$ in d) = 0 then raise exception 'texte introuvable'; end if;
  execute replace(d, $a$  if v_ver in ('1.0.24', '1.0.25', '1.0.26', '1.0.27') then v_ver := '1.0.23'; end if;$a$,
    $b$  if v_ver in ('1.0.24', '1.0.25', '1.0.26', '1.0.27') then v_ver := '1.0.23'; end if;
  -- 1.0.45 sans cadeau propre : donne le cadeau 1.0.44 à ceux qui ne l'ont pas eu (une seule fois en tout)
  if v_ver = '1.0.45' then v_ver := '1.0.44'; end if;$b$);
end $$;

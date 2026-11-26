-- Roue de la fortune : gains minimum 100 pieces, gains reglables par l'admin
-- (rc_config 'wheel' : w / wg = chances, p / pg = pieces par case ; cartes : 0)
-- Relancable.

create or replace function public.rc__wheel_p(p_gold boolean) returns int[]
  language sql stable security definer set search_path to 'public' as $f$
  select case when p_gold then public.rc__wheel_w('pg', array[200, 400, 0, 240, 600, 300, 0, 2000, 0])
              else public.rc__wheel_w('p', array[100, 200, 0, 120, 300, 150, 0, 800, 0]) end
$f$;
alter function public.rc__wheel_p(boolean) owner to rc_owner;

do $$
declare d text; n text;
begin
  -- rc_wheel : gains lus dans rc__wheel_p
  d := pg_get_functiondef('public.rc_wheel(text, text)'::regprocedure);
  if position('rc__wheel_p' in d) = 0 then
    n := replace(d, 'prize := array[80, 200, 0, 120, 400, 160, 0, 2000, 0];', 'prize := public.rc__wheel_p(true);');
    n := replace(n, 'prize := array[40, 100, 0, 60, 200, 80, 0, 600, 0];', 'prize := public.rc__wheel_p(false);');
    if (length(n) - length(replace(n, 'rc__wheel_p', ''))) / 11 <> 2 then raise exception 'rc_wheel : retouche impossible'; end if;
    execute n;
  end if;

  -- rc_notifs : gains de la roue envoyes a l'appli
  d := pg_get_functiondef('public.rc_notifs(text)'::regprocedure);
  if position('wheel_p' in d) = 0 then
    n := replace(d, '''wheel_gold'', public.rc__wheel_gold(p_device),',
      '''wheel_gold'', public.rc__wheel_gold(p_device),' || chr(10) ||
      '    ''wheel_p'', to_jsonb(public.rc__wheel_p(false)), ''wheel_pg'', to_jsonb(public.rc__wheel_p(true)),');
    if position('wheel_p' in n) = 0 then raise exception 'rc_notifs : retouche impossible'; end if;
    execute n;
  end if;

  -- rc__adm_cfg : gains en plus des chances
  d := pg_get_functiondef('public.rc__adm_cfg()'::regprocedure);
  if position('rc__wheel_p' in d) = 0 then
    n := replace(d, '''spins7'',', '''p'', to_jsonb(rc__wheel_p(false)), ''pg'', to_jsonb(rc__wheel_p(true)),' || chr(10) || '                                ''spins7'',');
    if position('rc__wheel_p' in n) = 0 then raise exception 'rc__adm_cfg : retouche impossible'; end if;
    execute n;
  end if;

  -- rc_admin_x wheel_set : accepte p / pg (pieces 0 a 100 000, cases carte a 0 sauf JACKPOT dore)
  d := pg_get_functiondef('public.rc_admin_x(text, text, text, text)'::regprocedure);
  if position('wheel_pv' in d) = 0 then
    n := replace(d, 'insert into rc_config (key, value) values (''wheel'', jsonb_build_object(''w'', j->''w'', ''wg'', j->''wg''))'
    on conflict (key) do update set value = excluded.value;','
'if j ? ''p'' then'
      if jsonb_array_length(j->''p'') <> 9 or jsonb_array_length(j->''pg'') <> 9 then raise exception ''il faut 9 cases''; end if;
      if exists (select 1 from jsonb_array_elements_text(j->''p'') a where a::int < 0 or a::int > 100000)
         or exists (select 1 from jsonb_array_elements_text(j->''pg'') a where a::int < 0 or a::int > 100000) then
        raise exception ''gain entre 0 et 100 000 pieces''; end if;
    end if;
    insert into rc_config (key, value) values (''wheel'',
      coalesce((select value from rc_config where key = ''wheel''), ''{}''::jsonb)
      || jsonb_build_object(''w'', j->''w'', ''wg'', j->''wg'')
      || case when j ? ''p'' then jsonb_build_object(
           ''p'', (select jsonb_agg(case when i in (3, 7, 9) then 0 else a::int end order by i) from jsonb_array_elements_text(j->''p'') with ordinality x(a, i)),
           ''pg'', (select jsonb_agg(case when i in (3, 7, 9) then 0 else a::int end order by i) from jsonb_array_elements_text(j->''pg'') with ordinality x(a, i)))
         else ''{}''::jsonb end) -- wheel_pv
    on conflict (key) do update set value = excluded.value;');'
    if position('wheel_pv' in n) = 0 then raise exception 'rc_admin_x : retouche impossible'; end if;
    execute n;
  end if;
end $$;

notify pgrst, 'reload schema';

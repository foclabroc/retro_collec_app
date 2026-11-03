create or replace function public.rc__wheel_w(p_k text, p_def int[])
       returns int[] language sql stable security definer set search_path to 'public' as $b$
        select coalesce(nullif(array(select x::int from jsonb_array_elements_text((select value -> p_k from public.rc_config where key = 'wheel')) x), '{}'::int[]), p_def)
      $b$ $f$;
    execute 'alter function public.rc__wheel_w(text, int[]) owner to rc_owner';
    execute n;
  end if;

  -- rc_cab_end : plafonds de points par seconde et prime du record réglables (live « cab_snake / cab_bricks / cab_dodge / cab_prime »)
  d := pg_get_functiondef('public.rc_cab_end(text, bigint, integer, text)'::regprocedure);
  if position('cab_snake' in d) = 0 then
    n := replace(d, 'v_rate := case x.game when ''snake'' then 250 when ''bricks'' then 450 else 120 end',
                    'v_rate := case x.game when ''snake'' then public.rc__cfg(''cab_snake'', 250) when ''bricks'' then public.rc__cfg(''cab_bricks'', 450) else public.rc__cfg(''cab_dodge'', 120) end');
    n := replace(n, 'v_gain := 20;', 'v_gain := public.rc__cfg(''cab_prime'', 20)::int;');
    if position('cab_snake' in n) = 0 or position('cab_prime' in n) = 0 then raise exception 'rc_cab_end : retouche impossible'; end if;
    execute n;
  end if;

  -- rc_upgrade_gift : cadeaux lus dans la table rc_upgrade_gifts (au lieu de la liste écrite dans la fonction)
  d := pg_get_functiondef('public.rc_upgrade_gift(text, text, text)'::regprocedure);
  if position('rc_upgrade_gifts' in d) = 0 then
    n := regexp_replace(d, 'from \(values.*?\) x\(ver, rw, out_at\)', 'from (select g.ver, g.reward, g.out_at from public.rc_upgrade_gifts g) x(ver, rw, out_at)');
    if position('rc_upgrade_gifts' in n) = 0 then raise exception 'rc_upgrade_gift : retouche impossible'; end if;
    execute n;
  end if;

  -- Actu : les publications masquées par l'admin n'apparaissent plus (3 versions de la liste)
  foreach n in array array['public.rc_feed_list(bigint)', 'public.rc_feed_list2(bigint)', 'public.rc_feed_list3(text, bigint)'] loop
    d := pg_get_functiondef(n::regprocedure);
    if position('not f.hidden' in d) = 0 and position('where f.id' in d) > 0 then
      execute replace(d, 'where f.id', 'where not f.hidden and f.id');
    end if;
  end loop;
end $$;

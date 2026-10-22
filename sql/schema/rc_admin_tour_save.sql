create or replace function public.rc_admin_tour_save(p_device text, p_sig text, p_data text)
 returns bigint
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare j jsonb; v_id bigint; v_st timestamptz; v_sz int; v_fee int; v_sp int; v_lots jsonb := '{}'::jsonb; k text; nm text;
begin
  perform public.rc__admin(p_device, p_sig, 'toursave|' || coalesce(p_data, ''));
  j := p_data::jsonb;
  v_id := nullif(j->>'id', '')::bigint;
  nm := left(trim(coalesce(j->>'name', '')), 40);
  if nm = '' then raise exception 'nom vide'; end if;
  if coalesce(j->>'game', '') not in ('c4', 'bs') then raise exception 'jeu inconnu'; end if;
  v_sz := coalesce((j->>'size')::int, 8);
  if v_sz not in (4, 8, 16) then raise exception 'places : 4, 8 ou 16'; end if;
  v_st := (j->>'start_at')::timestamptz;
  if v_st is null or v_st < now() + interval '1 minute' then raise exception 'le début doit être dans le futur'; end if;
  v_fee := least(greatest(coalesce((j->>'fee')::int, 0), 0), 10000);
  v_sp := case when coalesce((j->>'split')::int, 100) = 70 then 70 else 100 end;
  foreach k in array array['1', '2', '3'] loop
    if j->'lots' ? k then v_lots := v_lots || jsonb_build_object(k, public.rc__rw_clean(j->'lots'->k)); end if;
  end loop;
  if v_id is null then
    insert into public.rc_tour (name, game, size, start_at, fee, split, lots)
    values (nm, j->>'game', v_sz, v_st, v_fee, v_sp, v_lots) returning id into v_id;
    if coalesce((j->>'news')::boolean, true) then
      begin
        perform public.rc__feed_put(p_device, 'tournew', null, null, null, j->>'game', v_sz, nm);
      exception when others then null;
      end;
    end if;
  else
    if not exists (select 1 from public.rc_tour where id = v_id and status = 'open') then raise exception 'tournoi déjà commencé'; end if;
    if v_sz < (select count(*) from public.rc_tour_players where tid = v_id) then raise exception 'plus d''inscrits que de places'; end if;
    if v_fee <> (select t.fee from public.rc_tour t where t.id = v_id)
       and exists (select 1 from public.rc_tour_players where tid = v_id) then
      raise exception 'mise non modifiable : des joueurs sont inscrits';
    end if;
    update public.rc_tour set name = nm, game = j->>'game', size = v_sz, start_at = v_st, fee = v_fee, split = v_sp, lots = v_lots
     where id = v_id;
  end if;
  return v_id;
end $function$;

create or replace function public.rc_rn_solo_end(p_device text, p_run bigint, p_score integer, p_sig text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare r public.rc_rn_runs; cap int; sc int; old int;
begin
  perform public.rc__check(p_sig, p_device || '|rnsend|' || p_run || '|' || p_score);
  select * into r from public.rc_rn_runs where id = p_run and device = p_device for update;
  if r.id is null then raise exception 'partie inconnue'; end if;
  if r.ended_at is not null then raise exception 'partie terminée'; end if;
  cap := 100 + floor(24 * extract(epoch from (now() - r.started_at)))::int;
  sc := least(greatest(coalesce(p_score, 0), 0), cap);
  update public.rc_rn_runs set score = sc, ended_at = now() where id = p_run;
  select score into old from public.rc_rn_best where day = r.day and device = p_device;
  if sc > 0 and (old is null or sc > old) then
    insert into public.rc_rn_best (day, device, score, at) values (r.day, p_device, sc, now())
    on conflict (day, device) do update set score = excluded.score, at = excluded.at;
  end if;
  return public.rc_rn_solo_board(p_device) || jsonb_build_object('score', sc, 'record', sc > coalesce(old, 0), 'run_day', r.day);
end $function$;

CREATE OR REPLACE FUNCTION public.rc_admin_poll_new(p_device text, p_sig text, p_question text, p_options text, p_days integer)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare o jsonb; v_id bigint;
begin
  perform public.rc__admin(p_device, p_sig, 'pollnew|' || coalesce(p_question, '') || '|' || coalesce(p_options, '') || '|' || p_days);
  if trim(coalesce(p_question, '')) = '' then raise exception 'question vide'; end if;
  select coalesce(jsonb_agg(left(trim(x), 60)), '[]'::jsonb) into o
    from unnest(string_to_array(coalesce(p_options, ''), E'\n')) x where trim(x) <> '';
  if jsonb_array_length(o) < 2 or jsonb_array_length(o) > 4 then raise exception 'entre 2 et 4 réponses'; end if;
  if p_days < 1 or p_days > 30 then raise exception 'durée : 1 à 30 jours'; end if;
  update public.rc_polls set closed = true where not closed;  -- un seul sondage à la fois
  insert into public.rc_polls (question, options, ends_at) values (left(trim(p_question), 140), o, now() + make_interval(days => p_days))
  returning rc_polls.id into v_id;
  return v_id;
end $function$

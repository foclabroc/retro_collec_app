CREATE OR REPLACE FUNCTION public.rc_admin_mail(p_device text, p_sig text, p_pid text, p_title text, p_body text, p_coins integer, p_pixels integer, p_packs integer)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare d text; v_id bigint;
begin
  perform public.rc__admin(p_device, p_sig, 'mail|' || coalesce(p_pid, '') || '|' || coalesce(p_title, '') || '|'
                                            || p_coins || '|' || p_pixels || '|' || p_packs);
  if trim(coalesce(p_title, '')) = '' then raise exception 'titre vide'; end if;
  if p_coins < 0 or p_coins > 100000 or p_pixels < 0 or p_pixels > 1000 or p_packs < 0 or p_packs > 10 then
    raise exception 'montant invalide';
  end if;
  if coalesce(p_pid, '') <> '' then
    select device into d from public.rc_players where pid = p_pid;
    if d is null then raise exception 'joueur inconnu'; end if;
  end if;
  insert into public.rc_mail (device, title, body, coins, pixels, packs)
  values (d, left(trim(p_title), 80), left(coalesce(p_body, ''), 600), p_coins, p_pixels, p_packs) returning rc_mail.id into v_id;
  return v_id;
end $function$

CREATE OR REPLACE FUNCTION public.rc_admin_set_live(p_device text, p_sig text, p_values text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare j jsonb; k text; n numeric;
begin
  perform public.rc__admin(p_device, p_sig, 'live|' || coalesce(p_values, ''));
  j := p_values::jsonb;
  for k in select jsonb_object_keys(j) loop
    n := (j->>k)::numeric;
    if k in ('saga', 'holo', 'gold', 'fullart', 'pk') then
      if n < 0 or n > 50 then raise exception 'chance entre 0 et 50 %%'; end if;
    elsif k in ('mixte', 'console', 'premium', 'mystery', 'chest_coins', 'chest_pixels') then
      if n < 0 or n > 10000 or n <> round(n) then raise exception 'nombre entier entre 0 et 10000'; end if;
    else
      raise exception 'réglage inconnu : %', k;
    end if;
  end loop;
  update public.rc_config set value = value || j where key = 'live';
  return public.rc__live();
end $function$

create or replace function public.rc__rn_ok(p_device text)
 returns boolean
 language plpgsql
 stable security definer
 set search_path to 'public'
as $function$
declare v text;
begin
  select split_part(coalesce(app_ver, ''), '|', 1) into v from public.rc_players where device = p_device;
  if v is null or v = '' then return false; end if;
  return string_to_array(v, '.')::int[] >= array[1, 0, 32];
exception when others then
  return false;
end $function$;

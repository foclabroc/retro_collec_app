create or replace function public.rc__not_new(p_device text)
 returns void
 language plpgsql
 stable security definer
 set search_path to 'public'
as $function$
begin
  if exists (select 1 from public.rc_players where device = p_device and created_at > now() - interval '24 hours') then
    raise exception 'compte trop récent : possible 24 h après la création du compte';
  end if;
end $function$

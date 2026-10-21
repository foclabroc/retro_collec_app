create or replace function public.rc__rt_all()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
begin
  perform public.rc__rt_safe('rc_all', tg_argv[0], '{}'::jsonb);
  return null;
end $function$;

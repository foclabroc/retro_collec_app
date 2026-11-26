create or replace function public.rc__wheel_p(p_gold boolean) returns int[]
  language sql stable security definer set search_path to 'public' as $f$
  select case when p_gold then public.rc__wheel_w('pg', array[200, 400, 0, 240, 600, 300, 0, 2000, 0])
              else public.rc__wheel_w('p', array[100, 200, 0, 120, 300, 150, 0, 800, 0]) end
$f$;
alter function public.rc__wheel_p(boolean) owner to rc_owner;

create or replace function public.rc_admin_tour_cancel(p_device text, p_sig text, p_id bigint)
 returns void
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
begin
  perform public.rc__admin(p_device, p_sig, 'tourcancel|' || p_id);
  perform public.rc__tour_cancel(p_id);
end $function$;

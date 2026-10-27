create or replace function public.rc_rj_watch(p_id bigint)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare g public.rc_rj;
begin
  perform public.rc__rj_settle(p_id);
  select * into g from public.rc_rj where id = p_id and status in ('playing', 'done');
  if g.id is null then raise exception 'partie introuvable'; end if;
  return (public.rc__rj_json(g, g.p1) - 'msg' - 'reply') || jsonb_build_object('watch', true, 'me', public.rc__pinfo(g.p1));
end $function$;

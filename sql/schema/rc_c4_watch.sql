create or replace function public.rc_c4_watch(p_id bigint)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare g public.rc_c4;
begin
  perform public.rc__c4_settle(p_id);
  select * into g from public.rc_c4 where id = p_id and mode = 'live' and status in ('playing', 'done');
  if g.id is null then raise exception 'partie introuvable'; end if;
  -- vue du joueur 1 (side = 1, opp = joueur 2), sans les messages d'invitation
  return (public.rc__c4_json(g, g.p1) - 'msg' - 'reply')
         || jsonb_build_object('watch', true, 'me', public.rc__pinfo(g.p1), 'emo_me', g.emo1, 'emo_me_at', g.emo1_at);
end $function$;

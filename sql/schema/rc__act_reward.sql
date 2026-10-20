create or replace function public.rc__act_reward()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare j jsonb := to_jsonb(new); t text;
begin
  begin
    t := case tg_table_name
      when 'rc_events_got' then 'récupère l''événement « '
           || coalesce((select e.title from public.rc_events e where e.id = (j ->> 'event_id')::bigint), '?') || ' »'
      when 'rc_mail_got'   then 'récupère le courrier « '
           || coalesce((select m.title from public.rc_mail m where m.id = (j ->> 'mail_id')::bigint), '?') || ' »'
      when 'rc_trophy_got' then 'trophée « ' || coalesce(j ->> 'kind', '?') || ' » '
           || case j ->> 'tier' when '1' then 'bronze' when '2' then 'argent' when '3' then 'or' else coalesce(j ->> 'tier', '') end
      when 'rc_rewards_got' then 'récupère la récompense ' || coalesce(j ->> 'code', '?')
      when 'rc_milestones'  then 'palier de collection ' || coalesce(j ->> 'sys', '?') || ' n°' || coalesce(j ->> 'step', '?')
    end;
    perform public.rc__act(new.device, 'reward', 2, t);
  exception when others then null;
  end;
  return new;
end $function$;

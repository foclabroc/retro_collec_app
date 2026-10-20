CREATE OR REPLACE FUNCTION public.rc_poll_current(p_device text, p_sig text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare p public.rc_polls;
begin
  perform public.rc__check(p_sig, p_device || '|poll');
  select * into p from public.rc_polls x
   where not x.closed and x.ends_at > now()
     and not exists (select 1 from public.rc_poll_votes v where v.poll_id = x.id and v.device = p_device)
   order by x.id desc limit 1;
  if p.id is null then return null; end if;
  return jsonb_build_object('id', p.id, 'question', p.question, 'options', p.options, 'ends_at', p.ends_at);
end $function$

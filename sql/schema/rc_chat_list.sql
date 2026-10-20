CREATE OR REPLACE FUNCTION public.rc_chat_list(p_device text, p_after bigint)
 RETURNS TABLE(id bigint, pid text, name text, avatar integer, msg text, at timestamp with time zone, me boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  update public.rc_players set chat_seen = greatest(chat_seen, coalesce((select max(c.id) from public.rc_chat c), 0))
   where device = p_device;
  return query
    select x.id, x.pid, x.name, x.avatar, x.msg, x.at, x.me from (
      select c.id, p.pid, p.name, p.avatar, c.msg, c.created_at as at, c.device = p_device as me
        from public.rc_chat c join public.rc_players p on p.device = c.device
       where c.id > coalesce(p_after, 0) and not c.hidden
         and not exists (select 1 from public.rc_chat_reports r where r.msg_id = c.id and r.device = p_device)
       order by c.id desc limit 80) x
    order by x.id;
end $function$

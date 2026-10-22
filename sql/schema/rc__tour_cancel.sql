create or replace function public.rc__tour_cancel(p_tid bigint)
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare t public.rc_tour;
begin
  select * into t from public.rc_tour where id = p_tid for update;
  if t.id is null or t.status in ('done', 'cancelled') then return; end if;
  update public.rc_players p set coins = p.coins + tp.paid
    from public.rc_tour_players tp
   where tp.tid = p_tid and tp.paid > 0 and p.device = tp.device;
  update public.rc_tour_players set paid = 0 where tid = p_tid;
  update public.rc_tour_matches set status = 'done', reason = coalesce(reason, 'cancel') where tid = p_tid and status <> 'done';
  update public.rc_tour set status = 'cancelled', ended_at = now() where id = p_tid;
end $function$;

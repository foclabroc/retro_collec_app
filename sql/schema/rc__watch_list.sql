create or replace function public.rc__watch_list(p_game text, p_id bigint)
 returns jsonb
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select coalesce(jsonb_agg(jsonb_build_object('pid', p.pid, 'name', p.name, 'avatar', p.avatar) order by w.seen_at), '[]'::jsonb)
    from public.rc_watch w join public.rc_players p on p.device = w.device
   where w.game = p_game and w.gid = p_id and w.seen_at > now() - interval '50 seconds' $function$;

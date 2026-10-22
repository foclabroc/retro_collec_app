create or replace function public.rc__pinfo(p_device text)
 returns jsonb
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select jsonb_build_object('pid', p.pid, 'name', p.name, 'avatar', p.avatar,
                            'online', coalesce(p.seen_at > now() - interval '75 seconds', false))
    from public.rc_players p where p.device = p_device $function$

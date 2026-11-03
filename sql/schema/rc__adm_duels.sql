create or replace function public.rc__adm_duels()
 returns jsonb language sql stable security definer set search_path to 'public' as $$
  select coalesce(jsonb_agg(x order by x->>'created_at' desc), '[]'::jsonb) from (
    select jsonb_build_object('game', g.game, 'id', g.id, 'status', g.status, 'mode', g.mode, 'stake', g.stake, 'tour', g.tmatch is not null,
                              'created_at', g.created_at, 'move_at', g.move_at,
                              'p1', jsonb_build_object('pid', a.pid, 'name', a.name, 'avatar', a.avatar, 'online', a.seen_at > now() - interval '75 seconds'),
                              'p2', jsonb_build_object('pid', b.pid, 'name', b.name, 'avatar', b.avatar, 'online', b.seen_at > now() - interval '75 seconds')) x
      from (select 'c4' game, id, status, mode, stake, tmatch, created_at, move_at, p1, p2 from rc_c4 where status in ('invite', 'playing')
            union all select 'bs', id, status, mode, stake, tmatch, created_at, move_at, p1, p2 from rc_bs where status in ('invite', 'setup', 'playing')
            union all select case when kind = 'run' then 'rn' else 'rj' end, id, status, mode, stake, tmatch, created_at, move_at, p1, p2
                        from rc_rj where status in ('invite', 'playing')) g
      join rc_players a on a.device = g.p1 join rc_players b on b.device = g.p2) s
$$;

create or replace function public.rc__adm_allowed(p_role text)
 returns text[] language sql immutable as $$
  select array['check', 'accounts', 'player', 'links', 'stats', 'chat', 'market', 'mails', 'polls', 'events', 'log', 'feed',
               'act', 'card', 'statlist',
               'x:dash', 'x:players', 'x:player', 'x:econ', 'x:catalog', 'x:duels', 'x:sched', 'x:cheat', 'x:sanctions',
               'x:feed', 'x:cfg', 'x:gamedle', 'x:cab', 'x:admins']
       || case p_role
            when 'modo' then array['chatact', 'mremove', 'x:mute', 'x:sanction_add', 'x:sanction_lift', 'x:feed_hide',
                                   'x:note', 'x:alert_ok']
            when 'anim' then array['mail', 'mail2', 'maildel', 'pollnew', 'pollclose', 'evsave', 'evactive', 'toursave',
                                   'tourcancel', 'config:banner', 'x:sched_add', 'x:sched_del']
            else array[]::text[] end
$$;

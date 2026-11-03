create or replace function public.rc__express_def(p_day date)
 returns table(kind text, goal integer, reward jsonb)
 language plpgsql stable security definer set search_path to 'public' as $$
declare j jsonb; n int; v_h int := abs(hashtext('express#' || p_day::text));
begin
  select value into j from public.rc_config where key = 'express_fix';
  if j is not null and j->>'day' = p_day::text then
    return query select j->>'kind', (j->>'goal')::int, j->'reward'; return;
  end if;
  select value into j from public.rc_config where key = 'express';
  if j is not null and jsonb_typeof(j) = 'array' and jsonb_array_length(j) > 0 then
    n := jsonb_array_length(j);
    return query select j->(v_h % n)->>'kind', (j->(v_h % n)->>'goal')::int, j->(v_h % n)->'reward'; return;
  end if;
  return query select m.kind, m.goal, m.reward from (values
    (0, 'open', 2, '{"coins":80}'::jsonb), (1, 'gift', 1, '{"coins":60}'::jsonb), (2, 'trade', 1, '{"coins":100}'::jsonb),
    (3, 'win', 1, '{"coins":100}'::jsonb), (4, 'gamedle', 1, '{"coins":60}'::jsonb), (5, 'play', 2, '{"coins":80}'::jsonb),
    (6, 'new', 2, '{"coins":80}'::jsonb), (7, 'quiz', 5, '{"coins":60}'::jsonb), (8, 'sale', 1, '{"coins":80}'::jsonb),
    (9, 'free', 1, '{"coins":50}'::jsonb), (10, 'premium', 1, '{"coins":100}'::jsonb), (11, 'epic', 1, '{"coins":150,"pixels":1}'::jsonb)
  ) m(i, kind, goal, reward) where m.i = v_h % 12;
end $$;

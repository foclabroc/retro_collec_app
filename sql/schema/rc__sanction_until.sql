create or replace function public.rc__sanction_until(p_dev text, p_kind text)
 returns timestamptz language sql stable security definer set search_path to 'public' as $$
  select case when bool_or(until is null) then 'infinity'::timestamptz else max(until) end
    from public.rc_sanctions where device = p_dev and kind = p_kind and lifted_at is null and (until is null or until > now())
$$;

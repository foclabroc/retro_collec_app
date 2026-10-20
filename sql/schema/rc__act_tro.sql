create or replace function public.rc__act_tro()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare d int := coalesce(new.n, 0) - case when tg_op = 'UPDATE' then coalesce(old.n, 0) else 0 end;
begin
  begin
    if new.kind = 'recycle' then
      perform public.rc__act(new.device, 'recycle', 1, 'recycle ' || d || ' doublon(s)');
    elsif new.kind = 'fuse' then
      perform public.rc__act(new.device, 'fuse', 1, 'fusionne des cartes');
    end if;
  exception when others then null;
  end;
  return new;
end $function$;

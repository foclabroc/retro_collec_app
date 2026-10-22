create or replace function public.rc__act_tour()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare nm text;
begin
  begin
    select '« ' || name || ' »' into nm from public.rc_tour where id = coalesce(new.tid, old.tid);
    if tg_op = 'INSERT' then
      perform public.rc__act(new.device, 'tour', 2, 's''inscrit au tournoi ' || nm);
    elsif tg_op = 'DELETE' then
      perform public.rc__act(old.device, 'tour', 2, 'se désinscrit du tournoi ' || nm);
    elsif new.paid = 0 and old.paid > 0 then
      perform public.rc__act(new.device, 'tour', 2, 'remboursé : tournoi annulé ' || nm);
    elsif new.place is distinct from old.place and new.place is not null then
      perform public.rc__act(new.device, 'tour', 2,
        case new.place when 1 then 'gagne le tournoi ' when 2 then 'finaliste du tournoi ' else 'demi-finaliste du tournoi ' end || nm);
    end if;
  exception when others then null;
  end;
  return null;
end $function$;

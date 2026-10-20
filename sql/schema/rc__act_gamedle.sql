create or replace function public.rc__act_gamedle()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
begin
  begin
    if coalesce(new.won, false) and not coalesce(old.won, false) then
      perform public.rc__act(new.device, 'gamedle', 2,
        'trouve le Gamedle en ' || coalesce(array_length(new.guesses, 1), 0) || ' essai(s)');
    end if;
  exception when others then null;
  end;
  return new;
end $function$;

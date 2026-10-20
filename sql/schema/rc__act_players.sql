create or replace function public.rc__act_players()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare dc int := 0; dp int := 0; k text; t text; p int := 1;
begin
  begin
    if tg_op = 'INSERT' then
      perform public.rc__act(new.device, 'join', 2, 'crée son compte');
      return new;
    end if;
    dc := coalesce(new.coins, 0) - coalesce(old.coins, 0);
    dp := coalesce(new.pixels, 0) - coalesce(old.pixels, 0);
    if new.last_login is distinct from old.last_login then
      k := 'login'; t := 'connexion du jour (série ' || coalesce((to_jsonb(new) ->> 'streak'), '?') || ')';
    elsif new.wheel_day is distinct from old.wheel_day then
      k := 'wheel'; t := 'tourne la roue';
    elsif new.w_claim is distinct from old.w_claim then
      k := 'week';
      t := case when (coalesce(new.w_claim, 0) & 64) <> 0 and (coalesce(old.w_claim, 0) & 64) = 0
                then 'ouvre le coffre des défis' else 'récupère un défi de la semaine' end;
    elsif new.quiz_day is distinct from old.quiz_day or (to_jsonb(new) ->> 'quiz_gain') is distinct from (to_jsonb(old) ->> 'quiz_gain') then
      k := 'quiz'; t := 'quiz';
    elsif coalesce(new.lots, 0) > coalesce(old.lots, 0) then
      k := 'lot'; t := 'achète un lot de ' || (new.lots - coalesce(old.lots, 0)) || ' paquets';
    elsif coalesce(new.packs, 0) > coalesce(old.packs, 0) then
      k := 'open'; t := 'ouvre son paquet';
    elsif dc <> 0 or dp <> 0 then
      k := 'coins'; t := 'mouvement'; p := 0;
    else
      return new;
    end if;
    perform public.rc__act(new.device, k, p, t, null, null, null, dc, dp);
  exception when others then null;
  end;
  return new;
end $function$;

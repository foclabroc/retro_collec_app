create or replace function public.rc__act_pack()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare j jsonb := to_jsonb(new); n int := coalesce((j ->> 'packs')::int, 1);
begin
  begin
    perform public.rc__act(new.device, 'pack', 2,
      'prend ' || case when n > 1 then n || ' paquets ' else 'un paquet ' end || coalesce(j ->> 'kind', '?')
      || coalesce(' (' || nullif(j ->> 'sys', '') || ')', ''));
  exception when others then null;
  end;
  return new;
end $function$;

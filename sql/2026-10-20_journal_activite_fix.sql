-- Correctif : achat de paquets bloqué par le journal (relançable)

create or replace function public.rc__act_pack()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare j jsonb; n int;
begin
  begin  -- tout à l'intérieur : le journal ne doit jamais bloquer le jeu
    j := to_jsonb(new);
    -- packs = liste des paquets tirés (tableau de tableaux de cartes)
    n := case when jsonb_typeof(j -> 'packs') = 'array' then jsonb_array_length(j -> 'packs')
              when jsonb_typeof(j -> 'packs') = 'string' and left(j ->> 'packs', 1) = '['
                then jsonb_array_length((j ->> 'packs')::jsonb)
              else 1 end;
    perform public.rc__act(new.device, 'pack', 2,
      'prend ' || case when n > 1 then n || ' paquets ' else 'un paquet ' end || coalesce(j ->> 'kind', '?')
      || coalesce(' (' || nullif(j ->> 'sys', '') || ')', ''));
  exception when others then null;
  end;
  return new;
end $function$;

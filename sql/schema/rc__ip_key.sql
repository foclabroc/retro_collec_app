create or replace function public.rc__ip_key(p_ip text)
 returns text
 language plpgsql
 immutable
as $function$
declare a inet;
begin
  if p_ip is null or p_ip = '' then return null; end if;
  begin
    a := p_ip::inet;
  exception when others then
    return p_ip;  -- adresse illisible : gardée telle quelle (jamais bloquant)
  end;
  if family(a) = 6 and not a << '::ffff:0:0/96'::inet then
    return host(network(set_masklen(a, 64))) || '/64';
  end if;
  return host(a);
end $function$;

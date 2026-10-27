-- Pixel Trade : limite d'inscriptions / de connexions par IP comptée par bloc IPv6 /64 (relançable)
-- Avant : chaque adresse IPv6 comptait à part, or une box donne un /64 entier (des milliards d'adresses)
-- → on pouvait créer autant de comptes qu'on voulait. IPv4 et IPv4 dans IPv6 (::ffff:a.b.c.d) inchangés.
begin;

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
alter function public.rc__ip_key(text) owner to rc_owner;

create or replace function public.rc__ip()
 returns text
 language sql
 stable
 set search_path to 'public', 'extensions'
as $function$
  select case when k is null then null else encode(extensions.digest('ip|' || k, 'sha256'), 'hex') end
    from (select public.rc__ip_key(trim(split_part(coalesce(nullif(current_setting('request.headers', true), '')::json ->> 'x-forwarded-for', ''), ',', 1))) as k) x $function$;
alter function public.rc__ip() owner to rc_owner;

commit;

notify pgrst, 'reload schema';

-- Cadeau de passage en 1.0.16 : 500 pièces en dédommagement, une fois par joueur.
-- Appelé au démarrage par l'appli (1.0.16 et suivantes) avec sa version ;
-- pour une prochaine version : ajouter un « when » ci-dessous. Relançable.

create table if not exists public.rc_upgrade_got (
  device text not null,
  ver text not null,
  at timestamptz not null default now(),
  primary key (device, ver)
);
alter table public.rc_upgrade_got enable row level security;

create or replace function public.rc_upgrade_gift(p_device text, p_ver text, p_sig text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare
  v_coins int;
begin
  perform public.rc__check(p_sig, p_device || '|upgrade|' || p_ver);
  if not exists (select 1 from public.rc_players where device = p_device) then raise exception 'joueur inconnu'; end if;
  v_coins := case p_ver
    when '1.0.16' then 500
    else 0
  end;
  if v_coins = 0 then return jsonb_build_object('coins', 0); end if;
  insert into public.rc_upgrade_got (device, ver) values (p_device, p_ver) on conflict do nothing;
  if not found then return jsonb_build_object('coins', 0); end if;
  update public.rc_players set coins = coins + v_coins where device = p_device;
  return jsonb_build_object('coins', v_coins);
end $function$;

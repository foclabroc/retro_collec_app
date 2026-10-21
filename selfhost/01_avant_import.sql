-- ═══════════════════════════════════════════════════════════════════════════
-- Pixel Trade auto-hébergé — étape 1 : à lancer sur le Postgres de la maison,
-- AVANT d'importer la sauvegarde Supabase (psql -U postgres -d postgres -f ...).
-- Recrée les rôles et extensions que la base de Supabase utilise. Relançable.
-- Remplacer les deux mots de passe CHANGE_MOI_… avant de lancer.
-- ═══════════════════════════════════════════════════════════════════════════

-- Rôles présents dans les droits de la sauvegarde (Supabase)
do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon nologin noinherit; end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin noinherit; end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then create role service_role nologin noinherit bypassrls; end if;
  -- compte interne de Supabase (cité par des droits par défaut de la sauvegarde)
  if not exists (select 1 from pg_roles where rolname = 'supabase_admin') then create role supabase_admin nologin; end if;
  -- PostgREST se connecte avec ce rôle puis bascule en « anon »
  if not exists (select 1 from pg_roles where rolname = 'authenticator') then
    create role authenticator login noinherit password 'CHANGE_MOI_POSTGREST';
  end if;
  -- relais temps réel : se connecte seulement pour écouter (LISTEN rc_rt)
  if not exists (select 1 from pg_roles where rolname = 'rc_rt') then
    create role rc_rt login password 'CHANGE_MOI_REALTIME';
  end if;
end $$;

grant anon to authenticator;
grant usage on schema public to anon;

-- Extensions, dans le schéma « extensions » comme chez Supabase
-- (les fonctions appellent extensions.digest, crypt, gen_salt…)
create schema if not exists extensions;
grant usage on schema extensions to anon, authenticated, service_role;
create extension if not exists pgcrypto schema extensions;
create extension if not exists "uuid-ossp" schema extensions;

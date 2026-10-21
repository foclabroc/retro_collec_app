-- ═══════════════════════════════════════════════════════════════════════════
-- Pixel Trade maison : contrôle de sécurité du 21/10/2026. À lancer en postgres. Relançable.
--  1. Les objets du jeu passent au rôle rc_owner (PAS superutilisateur), comme chez
--     Supabase où « postgres » n'était pas superutilisateur. Les RPC security definer
--     tournent donc avec des droits limités à la base du jeu.
--  2. claude_rw ne passe plus par postgres (qui lui donnait la lecture des fichiers du PC
--     et des empreintes de mots de passe) mais par rc_owner.
--  3. Fonctions Rétro Jump / Rétro Jet restantes supprimées.
--  4. anon / authenticated : plus aucun droit direct sur les tables et séquences
--     (tout passe par les RPC), y compris pour les futures tables.
--  5. Toute future fonction interne rc__… est fermée à l'API automatiquement.
-- Tout ou rien.
-- ═══════════════════════════════════════════════════════════════════════════
\set ON_ERROR_STOP on
begin;

-- 1. Rôle propriétaire du jeu
do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'rc_owner') then
    create role rc_owner nologin;
  end if;
end $$;
alter role rc_owner nosuperuser nocreaterole nocreatedb noreplication nobypassrls;
grant usage, create on schema public to rc_owner;
grant usage on schema extensions to rc_owner;

-- 3. Restes de Rétro Jump / Rétro Jet (toutes signatures)
do $$
declare f record;
begin
  for f in
    select p.oid::regprocedure as sig
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in ('report_jump_chat','set_jet_stats','set_jump_coins','set_jump_avatar',
        'set_jump_profile','submit_jet_ghost','submit_jet_score','submit_jump_score',
        'rename_jump_player','send_jump_chat','set_jump_stats','submit_jump_ghost')
  loop
    execute format('drop function %s', f.sig);
  end loop;
end $$;

-- 1 (suite). Tout ce qui appartient à postgres dans « public » passe à rc_owner
do $$
declare o record;
begin
  -- tables (leurs séquences liées suivent), vues, tables étrangères
  for o in
    select c.oid::regclass as obj, c.relkind
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relowner = 'postgres'::regrole
      and c.relkind in ('r','p','v','m','f')
  loop
    execute format('alter %s %s owner to rc_owner',
      case o.relkind when 'v' then 'view' when 'm' then 'materialized view'
                     when 'f' then 'foreign table' else 'table' end, o.obj);
  end loop;
  -- séquences restantes (non liées à une colonne)
  for o in
    select c.oid::regclass as obj
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relowner = 'postgres'::regrole and c.relkind = 'S'
  loop
    execute format('alter sequence %s owner to rc_owner', o.obj);
  end loop;
  -- fonctions et procédures
  for o in
    select p.oid::regprocedure as obj, p.prokind
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proowner = 'postgres'::regrole and p.prokind in ('f','p')
  loop
    execute format('alter %s %s owner to rc_owner',
      case o.prokind when 'p' then 'procedure' else 'function' end, o.obj);
  end loop;
  -- types autonomes (enum, domaines)
  for o in
    select t.oid::regtype as obj
    from pg_type t join pg_namespace n on n.oid = t.typnamespace
    where n.nspname = 'public' and t.typowner = 'postgres'::regrole
      and t.typtype in ('e','d') 
  loop
    execute format('alter type %s owner to rc_owner', o.obj);
  end loop;
end $$;

-- 2. claude_rw : passe par rc_owner, plus par postgres
revoke postgres from claude_rw;
grant rc_owner to claude_rw with inherit true, set true;
revoke create on schema public from claude_rw;

-- 4. Plus de droits directs pour l'API sur les tables / séquences (RPC uniquement)
revoke all on all tables    in schema public from anon, authenticated, service_role;
revoke all on all sequences in schema public from anon, authenticated, service_role;
alter default privileges for role postgres revoke all on tables    from anon, authenticated, service_role;
alter default privileges for role postgres revoke all on sequences from anon, authenticated, service_role;
alter default privileges for role rc_owner revoke all on tables    from anon, authenticated, service_role;
alter default privileges for role rc_owner revoke all on sequences from anon, authenticated, service_role;

-- 5. Toute fonction interne rc__… créée ou remplacée est fermée à l'API
create or replace function public.rc__ddl_lock() returns event_trigger
 language plpgsql
 set search_path to 'public'
as $function$
declare o record;
begin
  for o in select * from pg_event_trigger_ddl_commands()
           where object_type = 'function' and schema_name = 'public'
  loop
    if o.object_identity like 'public.rc\_\_%' then
      execute 'revoke execute on function ' || o.object_identity || ' from public, anon, authenticated';
    end if;
  end loop;
end $function$;
alter function public.rc__ddl_lock() owner to postgres;
revoke execute on function public.rc__ddl_lock() from public, anon, authenticated;
drop event trigger if exists rc_ddl_lock;
create event trigger rc_ddl_lock on ddl_command_end
  when tag in ('CREATE FUNCTION', 'ALTER FUNCTION')
  execute function public.rc__ddl_lock();

-- Fonctions internes rc__ : on referme tout (au cas où)
do $$
declare f record;
begin
  for f in
    select p.oid::regprocedure as sig
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname like 'rc\_\_%'
  loop
    execute format('revoke execute on function %s from public, anon, authenticated', f.sig);
  end loop;
end $$;

commit;

-- ─── Contrôles ──────────────────────────────────────────────────────────────
select
  (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relowner = 'postgres'::regrole and c.relkind in ('r','S','v'))      as objets_encore_postgres,   -- 0
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proowner = 'postgres'::regrole and p.proname <> 'rc__ddl_lock')  as fonctions_encore_postgres, -- 0
  (select count(*) from information_schema.role_table_grants
    where grantee in ('anon','authenticated') and table_schema = 'public')                               as droits_tables_api,       -- 0
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname like 'rc\_\_%' and has_function_privilege('anon', p.oid, 'execute')) as internes_ouvertes, -- 0
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname like 'rc\_%' and p.proname not like 'rc\_\_%'
      and has_function_privilege('anon', p.oid, 'execute'))                                              as rpc_ouvertes,           -- ≈ 135
  pg_has_role('claude_rw', 'postgres', 'usage')                                                         as claude_via_postgres;     -- f

notify pgrst, 'reload schema';

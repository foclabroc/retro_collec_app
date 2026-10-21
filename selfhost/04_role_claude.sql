-- Pixel Trade maison : rôle « claude_rw » pour le serveur MCP local (selfhost/mcp-sql).
-- Passe par rc_owner (propriétaire du jeu, PAS superutilisateur, créé par 05_securite.sql) :
-- lecture + écriture sur la base du jeu, aucun accès aux fichiers du PC ni aux mots de passe.
-- À lancer APRÈS 05_securite.sql. Relançable. Remplacer CHANGE_MOI_CLAUDE (le même dans pgpass.conf).
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'claude_rw') then
    create role claude_rw login password 'CHANGE_MOI_CLAUDE';
  end if;
end $$;

alter role claude_rw nosuperuser nocreaterole nocreatedb noreplication;
revoke postgres from claude_rw;
grant rc_owner to claude_rw with inherit true, set true;

-- Contrôle : super = f, via_postgres = f, via_rc_owner = t
select r.rolsuper as super,
       pg_has_role('claude_rw', 'postgres', 'usage') as via_postgres,
       pg_has_role('claude_rw', 'rc_owner', 'usage') as via_rc_owner
from pg_roles r where r.rolname = 'claude_rw';

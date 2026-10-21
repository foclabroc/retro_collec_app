-- Pixel Trade maison : rôle « claude_rw » pour le serveur MCP local (selfhost/mcp-sql).
-- Lecture + écriture sur tout ce qui appartient à postgres (tables, fonctions du schéma public),
-- SANS être superutilisateur : pas de SET ROLE postgres, pas de COPY … PROGRAM, pas de fichiers du PC.
-- Relançable. Remplacer CHANGE_MOI_CLAUDE par un vrai mot de passe (le même dans pgpass.conf).
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'claude_rw') then
    create role claude_rw login password 'CHANGE_MOI_CLAUDE';
  end if;
end $$;

alter role claude_rw nosuperuser nocreaterole nocreatedb noreplication;
grant postgres to claude_rw with inherit true, set false;
grant usage, create on schema public to claude_rw;

-- Contrôle : super = f, peut_devenir_postgres = f, droits_postgres = t
select r.rolsuper as super,
       pg_has_role('claude_rw', 'postgres', 'set')    as peut_devenir_postgres,
       pg_has_role('claude_rw', 'postgres', 'usage')  as droits_postgres
from pg_roles r where r.rolname = 'claude_rw';

-- Pixel Trade maison : liste ce qui vient de Rétro Jump / Rétro Jet (lecture seule, ne supprime rien)
\echo '== Tables jump_* / jet_* =='
select c.relname as table, c.reltuples::bigint as lignes_env
from pg_class c join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relkind in ('r','p','v','m')
  and (c.relname like 'jump\_%' or c.relname like 'jet\_%')
order by 1;

\echo '== Fonctions jump_* / jet_* =='
select p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' as fonction
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and (p.proname like 'jump\_%' or p.proname like 'jet\_%')
order by 1;

\echo '== Fonctions rc_* qui citent jump_ / jet_ (doivent être 0) =='
select p.proname as fonction_rc
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname like 'rc%'
  and (p.prosrc ~ '\mjump_' or p.prosrc ~ '\mjet_');

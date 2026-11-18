-- Accès en LECTURE SEULE du rôle "lizmap" à la base courante (tous les schémas métier).
--
-- À exécuter en superutilisateur, connecté à la base à publier :
--
--   psql -h localhost -U postgres -d cotonou_db -v ON_ERROR_STOP=1 -f 02-droits-lecture-lizmap.sql
--
-- Relancer le script après la création de nouvelles tables (les droits ne portent que
-- sur les tables existantes). Pour l'édition web, ajouter ensuite INSERT/UPDATE/DELETE
-- sur les tables concernées et USAGE sur leurs séquences.

DO $$
DECLARE s text;
BEGIN
  EXECUTE format('GRANT CONNECT ON DATABASE %I TO lizmap', current_database());
  FOR s IN SELECT nspname FROM pg_namespace
           WHERE nspname NOT LIKE 'pg\_%'
             AND nspname NOT IN ('information_schema', 'topology', 'tiger', 'tiger_data')
  LOOP
    EXECUTE format('GRANT USAGE ON SCHEMA %I TO lizmap', s);
    EXECUTE format('GRANT SELECT ON ALL TABLES IN SCHEMA %I TO lizmap', s);
  END LOOP;
END $$;

-- Contrôle
SELECT count(*) AS tables_lisibles,
       count(*) FILTER (WHERE has_table_privilege('lizmap', c.oid, 'INSERT')) AS tables_modifiables
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relkind IN ('r', 'v', 'm')
  AND n.nspname NOT LIKE 'pg\_%' AND n.nspname <> 'information_schema'
  AND has_table_privilege('lizmap', c.oid, 'SELECT');

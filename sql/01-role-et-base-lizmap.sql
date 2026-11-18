-- Rôle "lizmap" et base "lizmap" pour les comptes, groupes et journaux de Lizmap.
--
-- À exécuter en superutilisateur, sur la base "postgres", en passant le mot de passe
-- par une variable psql (il n'apparaît ainsi ni dans le fichier ni dans l'historique) :
--
--   psql -h localhost -U postgres -d postgres -v ON_ERROR_STOP=1 -v pw="<mot de passe>" -f 01-role-et-base-lizmap.sql
--   psql -h localhost -U postgres -d lizmap   -v ON_ERROR_STOP=1 -c "CREATE EXTENSION IF NOT EXISTS postgis; CREATE SCHEMA IF NOT EXISTS lizmap AUTHORIZATION lizmap;"
--
-- Le script scripts/installer-lizmap.ps1 fait tout cela en générant le mot de passe.

CREATE ROLE lizmap LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE PASSWORD :'pw';
CREATE DATABASE lizmap OWNER lizmap ENCODING 'UTF8';

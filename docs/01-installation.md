# 1. Installer Lizmap sur le PostgreSQL/PostGIS de Windows

[Sommaire](../README.md) · Suivant : [2. Ce que Docker télécharge](02-images-docker.md)

## Le principe

| Où | Quoi |
|---|---|
| Windows | PostgreSQL + PostGIS (service Windows), QGIS Desktop + plugin Lizmap |
| Docker Desktop | Lizmap Web Client, QGIS Server, Redis, Nginx |

On part du dépôt officiel [3liz/lizmap-docker-compose](https://github.com/3liz/lizmap-docker-compose),
mais **sans son conteneur PostGIS** : Lizmap et QGIS Server se connectent au PostgreSQL déjà
installé sur Windows, par le nom `host.docker.internal` (le PC hôte vu depuis un conteneur).

Deux bases sont concernées :

- `lizmap` : comptes, groupes et droits de Lizmap (créée par l'installation) ;
- vos bases métier (ici `cotonou_db`), lues en lecture seule par le rôle `lizmap`.

## 0. Prérequis

| Logiciel | Version testée | Remarque |
|---|---|---|
| Windows | 11 Pro | |
| Docker Desktop | Engine 29.9, Compose 5.7 | Compose ≥ 2.24 obligatoire (balise `!override`) |
| PostgreSQL | 15.10 | installé avec l'installeur EDB, service `postgresql-x64-15` |
| PostGIS | 3.5.0 | via Stack Builder |
| QGIS Desktop | 3.34.12 LTR | QGIS Server doit être de version **égale ou supérieure** |
| Plugin QGIS « Lizmap » | 5.0.4 | depuis le gestionnaire d'extensions |
| Git pour Windows | 2.x | |

Espace disque : environ **3,1 Go** pour les images Docker (détail au [chapitre 2](02-images-docker.md)).
Si le disque C: est presque plein, déplacer d'abord les données de Docker Desktop :
*Settings > Resources > Advanced > Disk image location* (ici `D:\Docker`).

### Mot de passe du superutilisateur PostgreSQL

Les scripts se connectent en `postgres` **sans jamais demander ni afficher de mot de passe**.
Ils le lisent dans le fichier standard `pgpass.conf` :

```powershell
notepad "$env:APPDATA\postgresql\pgpass.conf"
```

```text
localhost:5432:*:postgres:VOTRE_MOT_DE_PASSE
```

### Autoriser les scripts PowerShell

Les fichiers téléchargés depuis GitHub sont marqués comme venant d'Internet :

```powershell
Get-ChildItem -Recurse .\scripts\*.ps1 | Unblock-File
```

Ou lancer chaque script avec `powershell -ExecutionPolicy Bypass -File .\scripts\....ps1`.

## 1. Faire le diagnostic du poste

```powershell
.\scripts\diagnostic-poste.ps1
```

Le script ne modifie rien. Il affiche :

- la version de Docker et l'emplacement de ses données ;
- le service PostgreSQL, sa version, `listen_addresses`, le port, PostGIS et les règles de `pg_hba.conf` ;
- les ports 5432, 8090 et 8091 ;
- l'espace libre de chaque disque ;
- QGIS, les plugins `lizmap` et `qgis_mcp_plugin`, le fichier de services PostgreSQL utilisé ;
- **le test décisif** : un conteneur peut-il s'authentifier auprès du PostgreSQL de Windows ?

Ce dernier test lance un petit conteneur `bash` qui ouvre une connexion vers
`host.docker.internal:5432` et envoie le message de démarrage du protocole PostgreSQL :

- réponse `R...` : PostgreSQL accepte l'origine de la connexion et demande un mot de passe. C'est gagné ;
- réponse `E... no pg_hba.conf entry` : la connexion arrive mais `pg_hba.conf` la refuse ;
- pas de réponse : PostgreSQL n'écoute pas sur l'adresse utilisée.

> Sur ce poste, PostgreSQL est resté en `listen_addresses = 'localhost'` avec le `pg_hba.conf`
> d'origine (`127.0.0.1/32` et `::1/128` en `scram-sha-256`) et la réponse a été `R` :
> Docker Desktop relaie les connexions vers `host.docker.internal` par la boucle locale de Windows,
> PostgreSQL les voit donc venir de `127.0.0.1`. Rien n'a été ouvert sur le réseau.
> Si votre réponse est différente, voir [Dépannage](07-depannage.md#un-conteneur-ne-peut-pas-joindre-postgresql).

## 2. Installer

### Méthode rapide

```powershell
.\scripts\installer-lizmap.ps1 -Dossier D:\lizmap
```

Paramètres utiles : `-LizmapTag 3.9`, `-QgisTag 3.44`, `-PgBin "C:\Program Files\PostgreSQL\15\bin"`, `-PgPort 5432`.
Le script refuse de continuer si le rôle `lizmap` existe déjà ou si les ports 8090/8091 sont pris.

Les étapes ci-dessous détaillent ce qu'il fait, pour comprendre ou pour le faire à la main.

### 2.1 Cloner le dépôt officiel en gardant les fins de ligne Unix

```powershell
git clone --depth 1 -c core.autocrlf=false https://github.com/3liz/lizmap-docker-compose.git D:\lizmap
```

`-c core.autocrlf=false` est indispensable : par défaut, Git pour Windows convertit les fichiers en
fins de ligne Windows (CRLF) et les scripts lancés dans les conteneurs Linux échouent
(`/bin/sh^M: not found`).

### 2.2 Écrire `.env` et `docker-compose.override.yml`

```powershell
Copy-Item docker\.env.example D:\lizmap\.env
Copy-Item docker\docker-compose.override.yml D:\lizmap\
```

- [`.env.example`](../docker/.env.example) : versions (`LIZMAP_VERSION_TAG=3.9`, `QGIS_VERSION_TAG=3.44`),
  ports **limités à ce PC** (`127.0.0.1:8090` pour Lizmap, `127.0.0.1:8091` pour QGIS Server) ;
- [`docker-compose.override.yml`](../docker/docker-compose.override.yml) : retire la dépendance de
  Lizmap envers le conteneur `postgis` et range ce dernier dans un profil jamais activé.

Docker Compose lit automatiquement `docker-compose.yml` puis `docker-compose.override.yml` : le dépôt
officiel reste intact, ce qui facilite ses mises à jour (`git pull`).

Contrôle :

```powershell
cd D:\lizmap
docker compose config --services    # doit lister lizmap, map, redis, web (pas postgis)
```

### 2.3 Télécharger les images

```powershell
docker compose pull
```

Environ 3,1 Go. Une erreur `TLS handshake timeout` vient de Docker Hub : relancer la commande
(le script fait jusqu'à trois essais). Le détail des images est au [chapitre 2](02-images-docker.md).

### 2.4 Configuration initiale

Le dépôt fournit `configure.bat`, mais il utilise `docker run -it` (il faut une vraie console) et
l'image `qgis-map-server:ltr-rc`, qui serait une deuxième image de 2,5 Go. On lance donc la même
commande sans `-it` et avec la version de QGIS Server déjà téléchargée :

```powershell
cd D:\lizmap
docker run --rm -u 1000:1000 `
  -e INSTALL_SOURCE=/install -e INSTALL_DEST=/lizmap -e "LIZMAP_DIR=D:\lizmap\lizmap" `
  -e QGSRV_SERVER_PLUGINPATH=/lizmap/plugins -e QGIS_VERSION_TAG=3.44 -e LIZMAP_VERSION_TAG=3.9 `
  -v "D:\lizmap:/install" -v "D:\lizmap\lizmap:/lizmap" -v "D:\lizmap:/src" `
  --entrypoint /src/configure.sh 3liz/qgis-map-server:3.44 _configure
```

Elle crée l'arborescence `D:\lizmap\lizmap`, des fichiers de configuration par défaut et installe les
plugins de QGIS Server (Lizmap server, atlasprint, wfsOutputExtension).

> **À ne plus relancer ensuite** : cette étape réécrit `lizmap\etc\profiles.d\lizmap_local.ini.php`
> avec l'hôte `db.lizmap` du conteneur PostGIS que l'on n'utilise pas.

### 2.5 Créer le rôle et la base `lizmap`

Le mot de passe du rôle `lizmap` ne sert qu'aux conteneurs : le script le génère au hasard et ne
l'affiche jamais. À la main :

```powershell
$psql = "C:\Program Files\PostgreSQL\15\bin\psql.exe"
& $psql -h localhost -U postgres -d postgres -v ON_ERROR_STOP=1 -v pw="UN_MOT_DE_PASSE_LONG" -f sql\01-role-et-base-lizmap.sql
& $psql -h localhost -U postgres -d lizmap -c "CREATE EXTENSION IF NOT EXISTS postgis; CREATE SCHEMA IF NOT EXISTS lizmap AUTHORIZATION lizmap;"
```

Le rôle n'a aucun privilège particulier (`NOSUPERUSER NOCREATEDB NOCREATEROLE`) : il possède sa base
`lizmap` et recevra plus tard un droit de **lecture** sur les bases publiées.

### 2.6 Déclarer la connexion dans les conteneurs

Deux fichiers, dans `D:\lizmap\lizmap\etc` (monté en lecture seule dans les conteneurs) :

| Fichier | Modèle | Rôle |
|---|---|---|
| `pg_service.conf` | [pg_service.conteneurs.conf.example](../config/pg_service.conteneurs.conf.example) | services PostgreSQL vus par Lizmap **et** QGIS Server |
| `profiles.d\lizmap_local.ini.php` | [lizmap_local.ini.php.example](../config/lizmap_local.ini.php.example) | base des comptes Lizmap |

Les deux pointent sur `host=host.docker.internal`, base `lizmap`, utilisateur `lizmap`, avec le mot de
passe de l'étape précédente. Ils contiennent un mot de passe : **ne jamais les publier** (le
[`.gitignore`](../.gitignore) de ce dépôt les exclut).

Enregistrer ces fichiers en **UTF-8 sans BOM avec des fins de ligne LF** (le script le fait ;
dans Notepad++ : *Encodage > UTF-8* et *Édition > Convertir les sauts de ligne > Unix*).

### 2.7 Démarrer et vérifier

```powershell
cd D:\lizmap
docker compose up -d
docker compose ps
```

| Vérification | Résultat attendu |
|---|---|
| http://localhost:8090 | page d'accueil de Lizmap |
| http://localhost:8091/lizmap/server.json | `qgis_server.metadata.version` = 3.44.x et plugin `lizmap_server` présent |
| tables du schéma `lizmap` de la base `lizmap` | une dizaine de tables (comptes, groupes, droits, journaux) créées par Lizmap au premier démarrage : la connexion conteneur → PostgreSQL fonctionne |

```powershell
& $psql -h localhost -U postgres -d lizmap -At -c "select count(*) from information_schema.tables where table_schema = 'lizmap'"
```

## 3. Première connexion

Ouvrir http://localhost:8090, *Connexion*, identifiant `admin`, mot de passe `admin`.
Lizmap demande aussitôt d'en choisir un nouveau. Faites-le vous-même : ce mot de passe sert aussi
au plugin Lizmap de QGIS Desktop ([chapitre 5](05-configurer-lizmap.md)).

## Arborescence obtenue

```text
D:\lizmap\                         clone de 3liz/lizmap-docker-compose
├── docker-compose.yml             fichier officiel, non modifié
├── docker-compose.override.yml    ce dépôt : sans conteneur PostGIS
├── .env                           ce dépôt : versions et ports
└── lizmap\
    ├── etc\                       monté en lecture seule dans les conteneurs (/srv/etc)
    │   ├── pg_service.conf        services PostgreSQL des conteneurs (secret)
    │   └── profiles.d\lizmap_local.ini.php   base des comptes (secret)
    ├── instances\                 vos projets QGIS publiés (/srv/projects)
    │   └── cotonou\               cotonou.qgs + cotonou.qgs.cfg + cotonou.qgs.png
    ├── plugins\                   plugins de QGIS Server
    └── var\lizmap-config\         configuration de Lizmap (répertoires, etc.)
```

Suivant : [2. Ce que Docker télécharge](02-images-docker.md)

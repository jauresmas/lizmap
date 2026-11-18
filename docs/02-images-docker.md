# 2. Ce que Docker télécharge

[Sommaire](../README.md) · Précédent : [1. Installation](01-installation.md) · Suivant : [3. Publier une base](03-publier-une-base.md)

Tout ce qui arrive sur le poste pendant l'installation, avec les versions exactes relevées le
17 novembre 2026. Rien de tout cela n'est stocké dans ce dépôt GitHub : tout est public et se
retélécharge (voir [plus bas](#pourquoi-les-images-ne-sont-pas-dans-ce-dépôt)).

## Les quatre images

| Service | Image | Rôle | Contenu (versions internes) | Taille sur disque |
|---|---|---|---|---|
| `map` | `3liz/qgis-map-server:3.44` | QGIS Server : produit les cartes (WMS), les données (WFS), les impressions | QGIS Server 3.44.15 « Solothurn », Ubuntu 24.04.5, Python 3.12.3, GDAL 3.8.4, Qt 5.15.13 | 2,56 Go |
| `lizmap` | `3liz/lizmap-web-client:3.9` | application web Lizmap (PHP-FPM) | Lizmap Web Client 3.9.12, PHP 8.3.36, Alpine 3.22 | 284 Mo |
| `redis` | `redis:8-alpine` | cache de Lizmap (sessions, tuiles) | Redis 8.10.3, Alpine 3.23 | 162 Mo |
| `web` | `nginx:alpine` | serveur web en façade, port 8090 | nginx 1.31.8, Alpine 3.24 | 94,5 Mo |

Total : **environ 3,1 Go**, quasi tout pour QGIS Server. Toutes en `linux/amd64`.

Empreintes (*digests*) des images téléchargées, pour retrouver exactement les mêmes :

```text
3liz/qgis-map-server:3.44    sha256:5803a254624e569d1906c613c86ad5ac14a9837a5712e1a9caba0627942b05a1
3liz/lizmap-web-client:3.9   sha256:33a3f70a817cf833d5bd443c39600e330d4d8a938b1e9d66c710622b708c45bc
redis:8-alpine               sha256:7958cfbb9d152f87dadfbc89f1b0b15938f0b81ff8982feb327476f4911935c3
nginx:alpine                 sha256:fed7e14be83cbd2661a75cdc5b872d936cf155d46c327084d30b8df19ae88d72
```

Pour les afficher chez vous :

```powershell
docker images --digests --format "table {{.Repository}}:{{.Tag}}\t{{.Digest}}\t{{.Size}}"
```

## Ce qui n'est *pas* téléchargé

| Image | Pourquoi |
|---|---|
| `3liz/postgis:17-3` | conteneur PostGIS du dépôt officiel, désactivé par `docker-compose.override.yml` : on utilise le PostgreSQL de Windows |
| `3liz/qgis-map-server:ltr-rc` | image utilisée par défaut par `configure.bat` ; on lance la configuration avec `3.44`, déjà présente (2,5 Go économisés) |

## Les autres téléchargements

| Quoi | D'où | Où sur le poste |
|---|---|---|
| dépôt `3liz/lizmap-docker-compose`, commit `59aaaf0` du 17/09/2026 | GitHub | `D:\lizmap` |
| plugin QGIS Server **Lizmap server 2.15.5** | plugins.qgis.org, via `qgis-plugin-manager` pendant la configuration | `D:\lizmap\lizmap\plugins\lizmap_server` |
| plugin QGIS Server **atlasprint 3.4.4** (impression d'atlas) | idem | `...\plugins\atlasprint` |
| plugin QGIS Server **wfsOutputExtension 1.8.3** (exports GeoJSON, CSV, etc.) | idem | `...\plugins\wfsOutputExtension` |
| image `bash:5.2` (~15 Mo) | Docker Hub, seulement pour le test réseau de `diagnostic-poste.ps1` | supprimable : `docker rmi bash:5.2` |

Les versions des plugins de QGIS Server se lisent sur http://localhost:8091/lizmap/server.json.

Côté QGIS Desktop, le plugin **Lizmap 5.0.4** s'installe depuis le gestionnaire d'extensions de QGIS.

## Ce que Docker crée

| Élément | Nom | Contenu |
|---|---|---|
| réseau | `lizmap_default` | réseau privé des quatre conteneurs |
| volume | `lizmap_redis_data` | cache Redis, sans importance (se reconstruit) |
| conteneurs | `lizmap-lizmap-1`, `lizmap-map-1`, `lizmap-redis-1`, `lizmap-web-1` | |

Tout le reste (configuration, projets, plugins) est dans des dossiers Windows montés dans les
conteneurs (`D:\lizmap\lizmap\...`), donc visible et sauvegardable comme n'importe quel dossier.
Les comptes Lizmap sont dans la base PostgreSQL `lizmap`.

Les images elles-mêmes sont dans le disque virtuel de Docker Desktop (WSL 2). Place occupée :

```powershell
docker system df
```

## Tags « flottants » et versions figées

`3.9`, `3.44`, `8-alpine` et `alpine` sont des tags **flottants** : un `docker compose pull` plus tard
apportera les correctifs (3.9.13, 3.44.16...). C'est en général ce que l'on veut.

Pour reproduire **exactement** cette installation, figer les images par leur empreinte :

- Lizmap et QGIS Server, dans `.env` (la référence `tag@sha256:...` est valide pour Docker) :

  ```ini
  LIZMAP_VERSION_TAG=3.9@sha256:33a3f70a817cf833d5bd443c39600e330d4d8a938b1e9d66c710622b708c45bc
  QGIS_VERSION_TAG=3.44@sha256:5803a254624e569d1906c613c86ad5ac14a9837a5712e1a9caba0627942b05a1
  ```

- Redis et Nginx, dans `docker-compose.override.yml` :

  ```yaml
  services:
    redis:
      image: redis:8-alpine@sha256:7958cfbb9d152f87dadfbc89f1b0b15938f0b81ff8982feb327476f4911935c3
    web:
      image: nginx:alpine@sha256:fed7e14be83cbd2661a75cdc5b872d936cf155d46c327084d30b8df19ae88d72
  ```

> Rien ne garantit qu'une ancienne empreinte restera disponible sur Docker Hub pendant des années.
> Pour une copie sûre, voir l'export ci-dessous.

## Mettre à jour

```powershell
cd D:\lizmap
docker compose pull
docker compose up -d
docker image prune      # supprime les anciennes versions devenues inutiles
```

Puis vérifier la version de QGIS Server dans `server.json`. Règle à respecter : **QGIS Server ≥ QGIS
Desktop**. Pour changer de version majeure (QGIS 3.40 → 3.44, Lizmap 3.9 → 3.10), modifier
`QGIS_VERSION_TAG` / `LIZMAP_VERSION_TAG` dans `.env` et lire les notes de version de Lizmap.

## Installer sur un PC sans Internet (ou garder une copie)

```powershell
docker save -o D:\sauvegarde\lizmap-images.tar `
  3liz/qgis-map-server:3.44 3liz/lizmap-web-client:3.9 redis:8-alpine nginx:alpine
```

Le fichier fait environ la taille des images (≈ 3 Go). Sur l'autre PC :

```powershell
docker load -i lizmap-images.tar
```

Copier aussi `D:\lizmap\lizmap\plugins` (les plugins de QGIS Server sont téléchargés pendant la
configuration, pas inclus dans les images).

## Pourquoi les images ne sont pas dans ce dépôt

- GitHub refuse les fichiers de plus de 100 Mo, et l'image QGIS Server fait 2,5 Go ;
- elles sont publiques sur Docker Hub, maintenues par 3Liz et Docker, et mises à jour pour les
  failles de sécurité : les recopier figerait des versions vieillissantes ;
- ce dépôt garde donc seulement **les références exactes** (tags + empreintes ci-dessus), ce qui
  suffit pour retrouver les mêmes images.

## Tout désinstaller

```powershell
cd D:\lizmap
docker compose down            # arrête et supprime les conteneurs (les dossiers et la base restent)
docker compose down -v         # idem + volume Redis
docker rmi 3liz/qgis-map-server:3.44 3liz/lizmap-web-client:3.9 redis:8-alpine nginx:alpine
```

Puis, si besoin, supprimer le dossier `D:\lizmap` et, dans PostgreSQL (en `postgres`) :

```sql
-- dans chaque base publiée (ex. cotonou_db) : retirer les droits donnés au rôle
DROP OWNED BY lizmap;
-- puis depuis la base postgres
DROP DATABASE lizmap;
DROP ROLE lizmap;
```

Suivant : [3. Publier une base PostGIS](03-publier-une-base.md)

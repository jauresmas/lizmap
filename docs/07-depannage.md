# 7. Dépannage

[Sommaire](../README.md) · Précédent : [6. Ajouter des couches](06-ajouter-des-couches.md)

Tous les problèmes ci-dessous ont été rencontrés pendant la réalisation de ce tutoriel.

## Où regarder

| Quoi | Commande ou fichier |
|---|---|
| état des conteneurs | `docker compose ps` (dans `D:\lizmap`) |
| QGIS Server | `docker compose logs -f map` |
| Lizmap | `docker compose logs lizmap`, `D:\lizmap\lizmap\var\lizmap-log\errors.log` |
| Nginx | `D:\lizmap\lizmap\var\log\nginx\lizmap_error.log` |
| versions et plugins de QGIS Server | http://localhost:8091/lizmap/server.json |
| plugin Lizmap de QGIS | panneau *Contrôles* de la fenêtre du plugin |

## Installation et Docker

### `/bin/sh^M: not found`, ou un conteneur qui redémarre en boucle

Le dépôt a été cloné avec les fins de ligne Windows (CRLF). Recloner :
`git clone -c core.autocrlf=false ...`, ou dans le clone existant :

```powershell
git config core.autocrlf false
git rm --cached -r . -q
git reset --hard
```

### `TLS handshake timeout` pendant `docker compose pull`

Docker Hub n'a pas répondu à temps. Relancer la commande ; les couches déjà reçues sont conservées.

### `the input device is not a TTY` avec `configure.bat`

`configure.bat` utilise `docker run -it`, impossible hors d'une console interactive (script, éditeur,
assistant). Utiliser la commande sans `-it` du [chapitre 1](01-installation.md#24-configuration-initiale).

### Lizmap ne trouve plus sa base (`db.lizmap`) après une nouvelle configuration

Relancer `configure.bat` / `configure.sh` réécrit `lizmap\etc\profiles.d\lizmap_local.ini.php` avec
l'hôte `db.lizmap` du conteneur PostGIS désactivé. Remettre `host=host.docker.internal` et le mot de
passe du rôle `lizmap` (celui de la section `[lizmap_local]` de `lizmap\etc\pg_service.conf`), puis
`docker compose restart lizmap`.

### `docker compose` refuse `!override`

Docker Compose trop ancien : il faut la version 2.24 ou plus (`docker compose version`). Mettre à
jour Docker Desktop.

### Le disque C: est plein

Les images occupent environ 3,1 Go dans le disque virtuel de Docker Desktop. Le déplacer :
*Settings > Resources > Advanced > Disk image location*.

## Connexion à PostgreSQL

### Un conteneur ne peut pas joindre PostgreSQL

Lancer `.\scripts\diagnostic-poste.ps1` et lire la dernière section.

- **`E ... no pg_hba.conf entry for host "172.x.x.x"`** : la connexion arrive, mais d'une adresse
  que `pg_hba.conf` n'autorise pas (cela dépend du mode réseau de Docker Desktop). Ajouter dans
  `pg_hba.conf` une ligne pour **cette adresse précise** et le seul rôle `lizmap` :

  ```text
  host    all    lizmap    172.x.x.0/24    scram-sha-256
  ```

  puis `Restart-Service postgresql-x64-15` (PowerShell administrateur).

- **pas de réponse du tout** : PostgreSQL n'écoute que sur `localhost` et la connexion n'arrive pas
  par là. Ajouter l'adresse de l'interface Docker/WSL à `listen_addresses` dans `postgresql.conf`
  (par exemple `listen_addresses = 'localhost,172.x.x.1'`), redémarrer le service.

> Ne pas ouvrir le port 5432 dans le pare-feu Windows pour le réseau : seuls les conteneurs de ce PC
> doivent pouvoir se connecter.

### `psql` semble bloqué, ou ignore les options

Le *conninfo* (`"service=cotonou_db"`, `"host=... dbname=..."`) doit être passé avec `-d`. En
premier argument sans `-d`, les options qui suivent sont mal interprétées et `psql` attend une saisie.

```powershell
psql -d "service=cotonou_db" -c "select current_user"
```

### Accents illisibles dans `psql` ou dans les scripts

- `psql` : `$env:PGCLIENTENCODING = "UTF8"` avant de le lancer ;
- PowerShell 5.1 lit un script sans BOM comme du texte ANSI : les `.ps1` de ce dépôt sont enregistrés
  en UTF-8 **avec** BOM. Les garder ainsi si vous les modifiez.

### Git Bash transforme `/www/lizmap/console.php` en `C:/Program Files/Git/www/...`

Conversion automatique des chemins de Git Bash. Préfixer la commande : `MSYS_NO_PATHCONV=1 docker compose exec ...`,
ou utiliser PowerShell.

### Une couche marche dans QGIS Desktop mais pas dans Lizmap

1. la source contient-elle `host=` ou `user=` au lieu de `service=` ? (chapitre 4) ;
2. le service existe-t-il dans `D:\lizmap\lizmap\etc\pg_service.conf` ? Après l'avoir ajouté :
   `docker compose restart map` ;
3. le rôle `lizmap` peut-il lire la table ? Relancer `.\scripts\publier-base.ps1 -Base <base>`.

## Projet QGIS

### Le projet passe en EPSG:32631 tout seul

QGIS adopte le SCR de la première couche ajoutée à un projet vide. Remettre EPSG:3857 **après** l'ajout des couches.

### Une couche ou un groupe disparaît de Lizmap

Un groupe et une couche portent le même nom. Renommer le groupe (« Équipements publics » / « Équipements »).

### La popup affiche `gid`, `osm_id`, `sources`...

Le widget « Caché » ne s'applique qu'au formulaire de QGIS Desktop. Cocher *Masquer dans WMS* dans
*Propriétés de la couche > Champs*, colonne *Configuration*. En PyQGIS 3.34 :
`layer.setFieldConfigurationFlag(i, Qgis.FieldConfigurationFlag.HideFromWms, True)`
(l'ancienne énumération `QgsField.ConfigurationFlag` n'existe plus).

## Plugin Lizmap

### Le bouton *Appliquer* ne produit pas de `.cfg`

Lire le panneau *Contrôles*. Causes rencontrées :

| Cause | Solution |
|---|---|
| aucun serveur déclaré, ou sans compte admin | panneau *Information*, ajouter `http://localhost:8090/` avec le compte admin |
| mode *Débutant* : services PostgreSQL interdits | panneau *Paramètres* : mode *Normal*, décocher *Prévenir les couches PostgreSQL d'utiliser un fichier de service* |
| simplification côté fournisseur (bloquant) | *Outils d'auto-correction* (à refaire après l'ajout de couches) |

### Les noms de couches sont devenus `Ilots_de_chaleur`...

C'est voulu : le plugin donne un *nom court* ASCII à chaque couche (son nom WMS). Le nom affiché
dans Lizmap reste le titre (« Îlots de chaleur »).

## Lizmap Web Client

### Le projet n'apparaît pas sur la page d'accueil

- `cotonou.qgs.cfg` est-il à côté de `cotonou.qgs` ? (format `.qgs`, pas `.qgz`) ;
- le répertoire est-il déclaré et le groupe de l'utilisateur a-t-il `lizmap.repositories.view` ?

```powershell
docker compose exec -T -u 1000 lizmap php /www/lizmap/console.php acl2:list
```

### Une requête WFS directe répond `403`

Normal pour un visiteur anonyme : Lizmap n'autorise le WFS qu'aux visiteurs qui ont ouvert la carte
(jeton de session) ou qui ont le droit `lizmap.tools.layer.export`. Les tables attributaires de la carte
fonctionnent ; pour un accès WFS externe, se connecter ou donner ce droit au groupe voulu.

## QGIS MCP

### `Could not connect to QGIS`

Le plugin QGIS MCP n'accepte qu'un client à la fois : une autre session (un autre assistant, un
autre terminal) le tient peut-être. Dans QGIS, panneau du plugin : *Stop Server* puis *Start Server*.

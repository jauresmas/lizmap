<#
.SYNOPSIS
    Installe Lizmap Web Client + QGIS Server (Docker) branchés sur le PostgreSQL/PostGIS de Windows.

.DESCRIPTION
    1. Vérifie Docker, psql, PostGIS et les ports.
    2. Clone 3liz/lizmap-docker-compose en gardant les fins de ligne Unix (LF).
    3. Écrit .env et docker-compose.override.yml (sans le conteneur PostGIS du dépôt).
    4. Télécharge les images (avec nouvelles tentatives si Docker Hub ne répond pas).
    5. Lance la configuration initiale (dossiers, plugins de QGIS Server).
    6. Crée le rôle et la base "lizmap" dans PostgreSQL avec un mot de passe aléatoire,
       écrit pg_service.conf et le profil des comptes Lizmap (le mot de passe n'est jamais affiché).
    7. Démarre la stack et vérifie qu'elle répond.

    Le superutilisateur PostgreSQL doit pouvoir se connecter sans saisie
    (%APPDATA%\postgresql\pgpass.conf ou variable PGPASSWORD).

.EXAMPLE
    .\scripts\installer-lizmap.ps1 -Dossier D:\lizmap
#>
[CmdletBinding()]
param(
    [string]$Dossier = 'D:\lizmap',
    [string]$LizmapTag = '3.9',
    [string]$QgisTag = '3.44',
    [string]$PgBin = 'C:\Program Files\PostgreSQL\15\bin',
    [int]$PgPort = 5432,
    [string]$PgSuperUtilisateur = 'postgres'
)

$ErrorActionPreference = 'Stop'
$depot = Split-Path -Parent $PSScriptRoot
$psql = Join-Path $PgBin 'psql.exe'
$utf8 = New-Object System.Text.UTF8Encoding($false)

function Etape($t) { Write-Host ""; Write-Host "==> $t" -ForegroundColor Cyan }
function Lire($chemin) { [IO.File]::ReadAllText($chemin, $utf8) }
function Ecrire($chemin, $texte) {
    # UTF-8 sans BOM et fins de ligne LF : lisibles par les conteneurs Linux
    [IO.File]::WriteAllText($chemin, (($texte -replace "`r`n", "`n").TrimEnd("`n") + "`n"), $utf8)
}
function Sql([string]$Base, [string]$Requete) {
    $r = $Requete | & $psql -h localhost -p $PgPort -U $PgSuperUtilisateur -d $Base -w -q -At -v ON_ERROR_STOP=1
    if ($LASTEXITCODE -ne 0) { throw "Échec de la requête SQL sur la base $Base" }
    return $r
}

# ---------------------------------------------------------------------------
Etape 'Vérifications'
# PowerShell 5.1 : une sortie d'erreur redirigée arrêterait le script avant notre message clair
$ErrorActionPreference = 'Continue'
docker info --format '{{.ServerVersion}}' *> $null
$dockerOk = $LASTEXITCODE -eq 0
$ErrorActionPreference = 'Stop'
if (-not $dockerOk) { throw 'Docker Desktop ne répond pas : le démarrer puis relancer.' }
if (-not (Test-Path $psql)) { throw "psql introuvable : $psql (paramètre -PgBin)" }
$version = Sql 'postgres' "select current_setting('server_version')"
Write-Host "PostgreSQL $version"
$postgis = Sql 'postgres' "select coalesce(default_version, '') from pg_available_extensions where name = 'postgis'"
if (-not $postgis) { throw "L'extension PostGIS n'est pas installée sur ce PostgreSQL." }
Write-Host "PostGIS $postgis disponible"
if ((Sql 'postgres' "select count(*) from pg_roles where rolname = 'lizmap'") -ne '0') {
    throw "Le rôle PostgreSQL 'lizmap' existe déjà : installation déjà faite ? (supprimer le rôle et la base 'lizmap' pour recommencer)"
}
foreach ($port in 8090, 8091) {
    if (Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue) {
        throw "Le port $port est déjà utilisé : changer LIZMAP_PORT / OWS_PORT dans docker\.env.example."
    }
}

# ---------------------------------------------------------------------------
Etape "Clonage de 3liz/lizmap-docker-compose dans $Dossier"
if (Test-Path (Join-Path $Dossier 'docker-compose.yml')) {
    Write-Host 'Déjà cloné : étape sautée.'
} else {
    # core.autocrlf=false : sans cela, Git pour Windows convertit les scripts en CRLF
    # et les conteneurs Linux ne démarrent plus (/bin/sh^M: not found).
    git clone --depth 1 -c core.autocrlf=false https://github.com/3liz/lizmap-docker-compose.git $Dossier
    if ($LASTEXITCODE -ne 0) { throw 'Échec du clonage.' }
}

# ---------------------------------------------------------------------------
Etape 'Fichiers .env et docker-compose.override.yml'
$envTxt = Lire (Join-Path $depot 'docker\.env.example')
$envTxt = $envTxt -replace '(?m)^LIZMAP_VERSION_TAG=.*$', "LIZMAP_VERSION_TAG=$LizmapTag"
$envTxt = $envTxt -replace '(?m)^QGIS_VERSION_TAG=.*$', "QGIS_VERSION_TAG=$QgisTag"
Ecrire (Join-Path $Dossier '.env') $envTxt
Ecrire (Join-Path $Dossier 'docker-compose.override.yml') (Lire (Join-Path $depot 'docker\docker-compose.override.yml'))

Push-Location $Dossier
try {
    docker compose config --services
    if ($LASTEXITCODE -ne 0) { throw 'docker compose config a échoué.' }

    # -----------------------------------------------------------------------
    Etape 'Téléchargement des images Docker (~3 Go)'
    for ($i = 1; $i -le 3; $i++) {
        docker compose pull
        if ($LASTEXITCODE -eq 0) { break }
        if ($i -eq 3) { throw 'Téléchargement impossible après 3 essais.' }
        Write-Warning "Docker Hub n'a pas répondu, nouvel essai ($($i + 1)/3) dans 15 s..."
        Start-Sleep -Seconds 15
    }

    # -----------------------------------------------------------------------
    Etape 'Configuration initiale (dossiers, plugins de QGIS Server)'
    $dest = Join-Path $Dossier 'lizmap'
    New-Item -ItemType Directory -Force $dest | Out-Null
    # Équivalent de configure.bat, sans "-it" (inutilisable hors console interactive)
    docker run --rm -u 1000:1000 `
        -e INSTALL_SOURCE=/install -e INSTALL_DEST=/lizmap -e "LIZMAP_DIR=$dest" `
        -e QGSRV_SERVER_PLUGINPATH=/lizmap/plugins `
        -e "QGIS_VERSION_TAG=$QgisTag" -e "LIZMAP_VERSION_TAG=$LizmapTag" `
        -v "${Dossier}:/install" -v "${dest}:/lizmap" -v "${Dossier}:/src" `
        --entrypoint /src/configure.sh "3liz/qgis-map-server:$QgisTag" _configure
    if ($LASTEXITCODE -ne 0) { throw 'La configuration initiale a échoué.' }

    # -----------------------------------------------------------------------
    Etape 'Rôle et base "lizmap" dans PostgreSQL'
    $car = [char[]]'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789'
    $octets = New-Object byte[] 28
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($octets)
    $mdp = -join ($octets | ForEach-Object { $car[$_ % $car.Length] })

    Sql 'postgres' ("\set pw '$mdp'`n" + (Lire (Join-Path $depot 'sql\01-role-et-base-lizmap.sql'))) | Out-Null
    Sql 'lizmap' 'CREATE EXTENSION IF NOT EXISTS postgis; CREATE SCHEMA IF NOT EXISTS lizmap AUTHORIZATION lizmap;' | Out-Null

    $etc = Join-Path $dest 'etc'
    Ecrire (Join-Path $etc 'pg_service.conf') @"
# Services PostgreSQL vus par les conteneurs Lizmap et QGIS Server.
# host.docker.internal = le PC Windows. Ajouter une section par base publiée
# (voir scripts\publier-base.ps1), avec le même nom que côté QGIS Desktop.

[lizmap_local]
host=host.docker.internal
port=$PgPort
dbname=lizmap
user=lizmap
password=$mdp
"@
    Ecrire (Join-Path $etc 'profiles.d\lizmap_local.ini.php') @"
[jdb]
lizlog=jauth

; Comptes, groupes et journaux de Lizmap : base "lizmap" du PostgreSQL de Windows
[jdb:jauth]
driver=pgsql
host=host.docker.internal
port=$PgPort
database=lizmap
user=lizmap
password="$mdp"
search_path=lizmap,public
"@
    Remove-Variable mdp
    Write-Host 'Mot de passe généré et écrit dans lizmap\etc (non affiché).'

    # -----------------------------------------------------------------------
    Etape 'Démarrage'
    docker compose up -d
    if ($LASTEXITCODE -ne 0) { throw 'docker compose up a échoué.' }

    $pret = $false
    for ($i = 0; $i -lt 60 -and -not $pret; $i++) {
        try { $pret = (Invoke-WebRequest 'http://127.0.0.1:8090/' -UseBasicParsing -TimeoutSec 5).StatusCode -eq 200 }
        catch { Start-Sleep -Seconds 2 }
    }
    if (-not $pret) { throw "Lizmap ne répond pas sur http://localhost:8090 : voir 'docker compose logs lizmap'." }

    # -----------------------------------------------------------------------
    Etape 'Vérifications'
    $srv = Invoke-RestMethod 'http://127.0.0.1:8091/lizmap/server.json' -TimeoutSec 30
    Write-Host ("QGIS Server : " + $srv.qgis_server.metadata.version + " - plugin lizmap_server " + $srv.qgis_server.plugins.lizmap_server.version)
    $tables = Sql 'lizmap' "select count(*) from information_schema.tables where table_schema = 'lizmap'"
    if ([int]$tables -gt 0) { Write-Host "Base lizmap : $tables tables créées par Lizmap (le conteneur atteint bien PostgreSQL)." }
    else { Write-Warning "Aucune table dans le schéma lizmap : voir 'docker compose logs lizmap'." }
    docker compose ps
}
finally {
    Pop-Location
}

Write-Host ""
Write-Host "Lizmap est prêt : http://localhost:8090  (admin / admin, changement demandé à la 1re connexion)" -ForegroundColor Green
Write-Host "Étape suivante : .\scripts\publier-base.ps1 -Base <ma_base>"

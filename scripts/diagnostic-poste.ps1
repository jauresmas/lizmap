<#
.SYNOPSIS
    Fait l'état des lieux du poste avant d'installer Lizmap (lecture seule).

.DESCRIPTION
    Vérifie Docker Desktop, le PostgreSQL/PostGIS de Windows, sa configuration réseau,
    les ports utilisés par Lizmap, l'espace disque, QGIS et ses plugins, puis teste
    qu'un conteneur Docker peut s'authentifier auprès de PostgreSQL via host.docker.internal.
    Ne modifie rien. Le test réseau télécharge une petite image (bash:5.2, ~15 Mo).

.EXAMPLE
    .\scripts\diagnostic-poste.ps1
    .\scripts\diagnostic-poste.ps1 -PgBin 'C:\Program Files\PostgreSQL\16\bin' -SansTestDocker
#>
[CmdletBinding()]
param(
    [string]$PgBin = 'C:\Program Files\PostgreSQL\15\bin',
    [string]$PgSuperUtilisateur = 'postgres',
    [int]$PgPort = 5432,
    [switch]$SansTestDocker
)

function Titre($t) { Write-Host ""; Write-Host "=== $t" -ForegroundColor Cyan }
function Ok($t)    { Write-Host "  [OK] $t" -ForegroundColor Green }
function Alerte($t){ Write-Host "  [!]  $t" -ForegroundColor Yellow }
function Info($t)  { Write-Host "       $t" }

Titre 'Docker'
$dv = docker version --format '{{.Server.Version}}' 2>$null
if ($LASTEXITCODE -eq 0 -and $dv) {
    Ok "Docker Engine $dv"
    Info ("Compose : " + (docker compose version --short 2>$null))
    $racine = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss\*' -ErrorAction SilentlyContinue |
               Where-Object DistributionName -eq 'docker-desktop' | Select-Object -First 1).BasePath
    if ($racine) { Info "Données Docker (WSL) : $racine" }
    docker ps --format '       {{.Names}}  ({{.Image}})  {{.Ports}}'
} else {
    Alerte 'Docker ne répond pas : démarrer Docker Desktop.'
}

Titre 'PostgreSQL / PostGIS'
$svc = Get-Service -Name 'postgresql*' -ErrorAction SilentlyContinue
if ($svc) { $svc | ForEach-Object { Ok "Service Windows $($_.Name) : $($_.Status)" } }
else { Alerte "Aucun service Windows postgresql* (PostgreSQL est peut-être dans Docker : adapter le tutoriel)." }

$psql = Join-Path $PgBin 'psql.exe'
if (Test-Path $psql) {
    $q = "select current_setting('server_version'), current_setting('listen_addresses'), current_setting('port'), " +
         "(select default_version from pg_available_extensions where name='postgis'), current_setting('hba_file')"
    $r = & $psql -h localhost -p $PgPort -U $PgSuperUtilisateur -d postgres -w -At -F '|' -c $q 2>$null
    if ($LASTEXITCODE -eq 0 -and $r) {
        $v = $r -split '\|'
        Ok "PostgreSQL $($v[0]) - listen_addresses='$($v[1])' - port $($v[2])"
        if ($v[3]) { Ok "PostGIS disponible : $($v[3])" } else { Alerte 'Extension PostGIS non installée.' }
        Info "pg_hba.conf : $($v[4])"
        if (Test-Path $v[4]) {
            Get-Content $v[4] | Where-Object { $_ -notmatch '^\s*#' -and $_.Trim() } | ForEach-Object { Info "  $_" }
        }
    } else {
        Alerte "Connexion impossible en $PgSuperUtilisateur sans mot de passe interactif."
        Info   "Renseigner %APPDATA%\postgresql\pgpass.conf (localhost:5432:*:postgres:motdepasse) ou `$env:PGPASSWORD."
    }
} else {
    Alerte "psql introuvable dans $PgBin (paramètre -PgBin)."
}

Titre 'Ports'
foreach ($port in $PgPort, 8090, 8091) {
    $c = Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($c) {
        $proc = (Get-Process -Id $c.OwningProcess -ErrorAction SilentlyContinue).ProcessName
        if ($port -eq $PgPort) { Ok "$port écouté par $proc ($($c.LocalAddress))" }
        elseif ($proc -eq 'com.docker.backend') { Info "$port publié par un conteneur Docker (Lizmap déjà démarré ?)" }
        else { Alerte "$port déjà utilisé par $proc : changer LIZMAP_PORT / OWS_PORT dans .env" }
    } elseif ($port -ne $PgPort) { Ok "$port libre" }
    else { Alerte "$port n'est pas écouté" }
}

Titre 'Espace disque'
Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Used -ne $null } | ForEach-Object {
    $libre = [math]::Round($_.Free / 1GB, 1)
    if ($libre -lt 5) { Alerte "$($_.Name): $libre Go libres (prévoir ~3 Go pour Lizmap : installer ailleurs)" }
    else { Ok "$($_.Name): $libre Go libres" }
}

Titre 'QGIS Desktop'
Get-ChildItem 'C:\Program Files' -Directory -Filter 'QGIS*' -ErrorAction SilentlyContinue | ForEach-Object { Ok $_.Name }
$plugins = Join-Path $env:APPDATA 'QGIS\QGIS3\profiles\default\python\plugins'
foreach ($p in 'lizmap', 'qgis_mcp_plugin') {
    $m = Join-Path $plugins "$p\metadata.txt"
    if (Test-Path $m) { Ok ("Plugin $p " + ((Select-String -Path $m -Pattern '^version=' | Select-Object -First 1).Line -replace 'version=', '')) }
    else { Alerte "Plugin $p absent (profil default)" }
}
$psf = [Environment]::GetEnvironmentVariable('PGSERVICEFILE', 'User')
if ($psf) { Info "PGSERVICEFILE (utilisateur) = $psf" }
else { Info "Fichier de services par défaut : $env:APPDATA\postgresql\.pg_service.conf" }

if (-not $SansTestDocker -and $dv) {
    Titre 'Un conteneur peut-il s''authentifier auprès de PostgreSQL ?'
    # Envoie un message de démarrage du protocole PostgreSQL (utilisateur fictif "sonde")
    # et lit la réponse : 'R' = pg_hba accepte l'hôte (le serveur demande un mot de passe,
    # ex. "R........SCRAM-SHA-256.."), 'E ... no pg_hba.conf entry' = l'hôte est refusé.
    # Pas de guillemets doubles dans $sonde : PowerShell 5.1 les transmet mal aux programmes externes.
    $sonde = 'exec 3<>/dev/tcp/host.docker.internal/' + $PgPort + '; ' +
             'printf ''\x00\x00\x00\x26\x00\x03\x00\x00user\x00sonde\x00database\x00postgres\x00\x00'' >&3; ' +
             'timeout 3 cat <&3 | head -c 200 | tr ''\000-\037\177-\377'' ''.'''
    docker pull -q bash:5.2 *> $null
    $rep = docker run --rm bash:5.2 bash -c $sonde 2>$null
    if ("$rep" -match '^R') { Ok "PostgreSQL accepte les connexions venant des conteneurs (réponse : $rep)" }
    elseif ("$rep" -match 'pg_hba') { Alerte "Refusé par pg_hba.conf : $rep" }
    else { Alerte "Réponse inattendue : $rep" }
}

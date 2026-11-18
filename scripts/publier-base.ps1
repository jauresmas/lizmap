<#
.SYNOPSIS
    Rend une base PostGIS publiable dans Lizmap (lecture seule).

.DESCRIPTION
    1. Donne au rôle "lizmap" le droit de lire toutes les tables de la base.
    2. Déclare le service côté conteneurs (host.docker.internal, utilisateur lizmap).
    3. Déclare le MÊME nom de service côté QGIS Desktop (localhost).
    4. Redémarre QGIS Server et teste la connexion des deux côtés.
    Peut être relancé sans risque (les étapes déjà faites sont sautées).

.EXAMPLE
    .\scripts\publier-base.ps1 -Base cotonou_db
    .\scripts\publier-base.ps1 -Base ma_base -Service ma_base_web -UtilisateurDesktop sig_admin
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Base,
    [string]$Service = $Base,
    [string]$Dossier = 'D:\lizmap',
    [string]$UtilisateurDesktop = 'postgres',
    [string]$PgBin = 'C:\Program Files\PostgreSQL\15\bin',
    [int]$PgPort = 5432,
    [string]$PgSuperUtilisateur = 'postgres'
)

$ErrorActionPreference = 'Stop'
$depot = Split-Path -Parent $PSScriptRoot
$psql = Join-Path $PgBin 'psql.exe'
$utf8 = New-Object System.Text.UTF8Encoding($false)
function Etape($t) { Write-Host ""; Write-Host "==> $t" -ForegroundColor Cyan }

# ---------------------------------------------------------------------------
Etape "Droits de lecture du rôle lizmap sur $Base"
& $psql -h localhost -p $PgPort -U $PgSuperUtilisateur -d $Base -w -q -v ON_ERROR_STOP=1 -f (Join-Path $depot 'sql\02-droits-lecture-lizmap.sql')
if ($LASTEXITCODE -ne 0) { throw "Échec des droits sur $Base" }

# ---------------------------------------------------------------------------
Etape "Service [$Service] côté conteneurs"
$fc = Join-Path $Dossier 'lizmap\etc\pg_service.conf'
$txt = [IO.File]::ReadAllText($fc, $utf8)
if ($txt -match "(?m)^\[$([regex]::Escape($Service))\]") {
    Write-Host 'Déjà présent.'
} else {
    $mdp = ([regex]::Match($txt, '(?ms)^\[lizmap_local\].*?^password=(\S+)')).Groups[1].Value
    if (-not $mdp) { throw "Mot de passe du rôle lizmap introuvable dans $fc" }
    $ajout = "`n[$Service]`nhost=host.docker.internal`nport=$PgPort`ndbname=$Base`nuser=lizmap`npassword=$mdp`n"
    [IO.File]::WriteAllText($fc, $txt.TrimEnd("`n") + "`n" + $ajout, $utf8)
    Remove-Variable mdp
    Write-Host "Ajouté dans $fc"
}

# ---------------------------------------------------------------------------
Etape "Service [$Service] côté QGIS Desktop"
$fd = [Environment]::GetEnvironmentVariable('PGSERVICEFILE', 'User')
if (-not $fd) { $fd = $env:PGSERVICEFILE }
if (-not $fd) { $fd = Join-Path $env:APPDATA 'postgresql\.pg_service.conf' }
if (-not (Test-Path $fd)) {
    New-Item -ItemType Directory -Force (Split-Path $fd) | Out-Null
    [IO.File]::WriteAllText($fd, "# Services PostgreSQL de QGIS Desktop`r`n", $utf8)
}
$brut = [IO.File]::ReadAllText($fd, $utf8)
if ($brut -match "(?m)^\[$([regex]::Escape($Service))\]") {
    Write-Host "Déjà présent dans $fd"
} else {
    $nl = if ($brut -match "`r`n") { "`r`n" } else { "`n" }
    $ajout = "${nl}# Publié dans Lizmap : même nom de service côté conteneurs (host.docker.internal)$nl" +
             "[$Service]${nl}host=localhost${nl}port=$PgPort${nl}dbname=$Base${nl}user=$UtilisateurDesktop$nl"
    if (-not $brut.EndsWith($nl)) { $ajout = $nl + $ajout }
    [IO.File]::AppendAllText($fd, $ajout, $utf8)
    Write-Host "Ajouté dans $fd"
}

# ---------------------------------------------------------------------------
Etape 'Test côté QGIS Desktop'
# Attention : avec psql, le conninfo doit passer par -d (sinon les options suivantes sont ignorées).
$r = & $psql -w -At -d "service=$Service" -c "select current_user || '@' || current_database()"
if ($LASTEXITCODE -eq 0) { Write-Host "OK : $r" }
else { Write-Warning "Connexion par service impossible sans mot de passe : ajouter $UtilisateurDesktop dans pgpass.conf." }

# ---------------------------------------------------------------------------
Etape 'Redémarrage de QGIS Server et test côté conteneurs'
Push-Location $Dossier
try {
    docker compose restart map
    $py = @"
from qgis.core import QgsApplication, QgsDataSourceUri, QgsProviderRegistry
app = QgsApplication([], False); app.initQgis()
uri = QgsDataSourceUri(); uri.setService('$Service')
conn = QgsProviderRegistry.instance().providerMetadata('postgres').createConnection(uri.uri(), {})
print('OK :', conn.executeSql("select current_user || '@' || current_database()")[0][0], '-', len(conn.tables()), 'tables visibles')
"@
    # PowerShell 5.1 : avec ErrorActionPreference=Stop, la moindre ligne d'avertissement envoyée
    # sur stderr par un programme externe redirigé arrête le script. On l'autorise le temps du test.
    $ErrorActionPreference = 'Continue'
    $py | docker compose exec -T -e QT_QPA_PLATFORM=offscreen -e XDG_RUNTIME_DIR=/tmp map python3 - 2>$null
    if ($LASTEXITCODE -ne 0) { Write-Warning "QGIS Server n'arrive pas à se connecter avec le service $Service." }
}
finally {
    Pop-Location
}

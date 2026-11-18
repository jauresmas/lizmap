<#
.SYNOPSIS
    Crée un répertoire Lizmap (dossier de projets) et ses droits, sans passer par l'interface d'administration.

.DESCRIPTION
    - crée le dossier lizmap\instances\<Cle> ;
    - déclare le répertoire dans Lizmap (console.php repository:create) ;
    - donne le droit de consultation aux groupes connectés (et aux visiteurs anonymes avec -Public) ;
    - donne le droit d'export des couches aux groupes connectés.

.EXAMPLE
    .\scripts\creer-repertoire-lizmap.ps1 -Cle cotonou -Libelle "Cotonou" -Public
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidatePattern('^[a-z0-9_]+$')][string]$Cle,
    [string]$Libelle = $Cle,
    [string]$Dossier = 'D:\lizmap',
    [switch]$Public
)

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force (Join-Path $Dossier "lizmap\instances\$Cle") | Out-Null

function Console-Lizmap { docker compose exec -T -u 1000 lizmap php /www/lizmap/console.php @args }

Push-Location $Dossier
try {
    $config = Join-Path $Dossier 'lizmap\var\lizmap-config\lizmapConfig.ini.php'
    if ((Test-Path $config) -and (Select-String -Path $config -Pattern "^\[repository:$Cle\]" -Quiet)) {
        Write-Host "Le répertoire $Cle existe déjà : seuls les droits sont (re)donnés."
    } else {
        Console-Lizmap repository:create $Cle $Libelle "$Cle/" true
        if ($LASTEXITCODE -ne 0) { throw "Création du répertoire $Cle impossible." }
    }

    # Droits déjà donnés sur ce répertoire (le groupe des anonymes s'affiche sans identifiant)
    $existants = Console-Lizmap acl2:list | ForEach-Object {
        $c = @($_ -split '\|' | ForEach-Object { $_.Trim() })
        if ($c.Count -ge 5 -and $c[4] -eq $Cle) { "$(if ($c[1]) { $c[1] } else { '__anonymous' }) $($c[3])" }
    }
    function Donner($groupe, $droit) {
        if ($existants -contains "$groupe $droit") { Write-Host "  déjà donné : $groupe  $droit" }
        else {
            Console-Lizmap acl2:add $groupe $droit $Cle | Out-Null
            Write-Host "  ajouté      : $groupe  $droit"
        }
    }

    $lecteurs = @('users', 'publishers', 'admins')
    if ($Public) { $lecteurs = @('__anonymous') + $lecteurs }
    foreach ($g in $lecteurs) { Donner $g 'lizmap.repositories.view' }
    foreach ($g in 'users', 'publishers', 'admins') { Donner $g 'lizmap.tools.layer.export' }
    Donner 'admins' 'lizmap.tools.displayGetCapabilitiesLinks'

    Write-Host ""
    Console-Lizmap acl2:list | Select-String -Pattern " $Cle "
}
finally {
    Pop-Location
}
Write-Host ""
Write-Host "Déposer le projet (.qgs + .qgs.cfg) dans $Dossier\lizmap\instances\$Cle" -ForegroundColor Green

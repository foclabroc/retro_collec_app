# Sauvegarde de nuit de la base Pixel Trade (schéma public), garde 7 jours.
# Lancé par la tâche planifiée « PixelTrade-Sauvegarde » (voir README, section 6).
# Mot de passe : D:\pixeltrade\pgpass.conf (jamais dans le dépôt).

$ErrorActionPreference = 'Stop'

$PgBin   = 'C:\Program Files\PostgreSQL\17\bin'
$Dossier = 'D:\sauvegardes'
$Journal = 'D:\pixeltrade\sauvegarde.log'
$Jours   = 7

$env:PGPASSFILE = 'D:\pixeltrade\pgpass.conf'

function Note($texte) {
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $texte" | Add-Content -Path $Journal -Encoding UTF8
}

try {
    New-Item -ItemType Directory -Force -Path $Dossier | Out-Null

    $nom   = 'rc_' + (Get-Date -Format 'yyyy-MM-dd_HHmm') + '.dump'
    $final = Join-Path $Dossier $nom
    $temp  = "$final.part"

    # 1. Dump au format custom (compressé, restaurable avec pg_restore)
    & "$PgBin\pg_dump.exe" -h 127.0.0.1 -U postgres -d postgres -n public -Fc -f $temp
    if ($LASTEXITCODE -ne 0) { throw "pg_dump a échoué (code $LASTEXITCODE)" }

    # 2. Vérifie que le fichier est lisible avant de le garder
    & "$PgBin\pg_restore.exe" -l $temp | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "fichier illisible par pg_restore (code $LASTEXITCODE)" }

    Move-Item -Force $temp $final
    $taille = [math]::Round((Get-Item $final).Length / 1MB, 1)
    Note "OK  $nom  ($taille Mo)"

    # 3. Rotation (seulement après une sauvegarde réussie) : rc_*.dump de plus de $Jours jours
    $vieux = Get-ChildItem $Dossier -Filter 'rc_*.dump' |
             Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$Jours) }
    foreach ($f in $vieux) {
        Remove-Item $f.FullName
        Note "supprimé  $($f.Name)"
    }
}
catch {
    if ($temp -and (Test-Path $temp)) { Remove-Item $temp -ErrorAction SilentlyContinue }
    Note "ERREUR  $($_.Exception.Message)"
    exit 1
}

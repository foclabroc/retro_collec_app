# Sauvegarde de nuit complète de Pixel Trade, garde 7 jours.
# Lancé par la tâche planifiée « PixelTrade-Sauvegarde » (voir README, section 6).
# Mot de passe : D:\pixeltrade\pgpass.conf (jamais dans le dépôt).
#
# Contenu de chaque nuit (dans $Dossier) :
#   rc_AAAA-MM-JJ_HHMM.dump          schéma public (restauration normale, voir README)
#   rc_full_AAAA-MM-JJ_HHMM.dump     toute la base (extensions, autres schémas)
#   rc_globals_AAAA-MM-JJ_HHMM.sql   rôles et mots de passe hachés (rc_owner, rc_rt, claude_rw, …)
#   rc_config_AAAA-MM-JJ_HHMM.zip    réglages : PostgreSQL (postgresql.conf, pg_hba.conf), PostgREST, relais,
#                                    mcp-sql, Caddyfile, DuckDNS, tâches planifiées, services NSSM
#   pk\                              images Pokémon (copie miroir, pas de rotation)
# ATTENTION : rc_config contient des secrets (Caddyfile, postgrest.conf) : ne pas le mettre en ligne.
# Copie hors du disque D: : renseigner $Copie (autre disque, clé USB, dossier synchronisé), vide = pas de copie.

$ErrorActionPreference = 'Stop'

$PgBin   = 'C:\Program Files\PostgreSQL\17\bin'
$PgData  = 'C:\Program Files\PostgreSQL\17\data'
$Dossier = 'D:\pixeltrade\sauvegardes'
$Journal = 'D:\pixeltrade\sauvegarde.log'
$Copie   = ''
$Jours   = 7

# Dossiers / fichiers de réglages à archiver (ceux qui n'existent pas sont ignorés)
$Config  = @(
    'C:\pixeltrade\postgrest\postgrest.conf',
    'C:\pixeltrade\rc-realtime\server.js',
    'C:\pixeltrade\rc-realtime\package.json',
    'C:\pixeltrade\rc-realtime\package-lock.json',
    'D:\pixeltrade\rc-realtime',
    'D:\pixeltrade\mcp-sql',
    'D:\pixeltrade\sql',
    'D:\pixeltrade\securite.md',
    'C:\caddy\Caddyfile',
    'C:\caddy\update-duckdns.ps1',
    "$PgData\postgresql.conf",
    "$PgData\pg_hba.conf"
)

$env:PGPASSFILE = 'D:\pixeltrade\pgpass.conf'
$erreurs = 0

function Note($texte) {
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $texte" | Add-Content -Path $Journal -Encoding UTF8
}

# Une partie annexe qui échoue est notée mais n'empêche pas les autres
function Partie($nom, [scriptblock]$code) {
    try { & $code }
    catch { $script:erreurs++; Note "ERREUR  $nom : $($_.Exception.Message)" }
}

try {
    New-Item -ItemType Directory -Force -Path $Dossier | Out-Null
    $date = Get-Date -Format 'yyyy-MM-dd_HHmm'

    # 1. Schéma public, format custom (compressé, restaurable avec pg_restore) : la sauvegarde principale
    $nom   = "rc_$date.dump"
    $final = Join-Path $Dossier $nom
    $temp  = "$final.part"
    & "$PgBin\pg_dump.exe" -h 127.0.0.1 -U postgres -d postgres -n public -Fc -f $temp
    if ($LASTEXITCODE -ne 0) { throw "pg_dump a échoué (code $LASTEXITCODE)" }
    & "$PgBin\pg_restore.exe" -l $temp | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "fichier illisible par pg_restore (code $LASTEXITCODE)" }
    Move-Item -Force $temp $final
    Note "OK  $nom  ($([math]::Round((Get-Item $final).Length / 1MB, 1)) Mo)"
}
catch {
    if ($temp -and (Test-Path $temp)) { Remove-Item $temp -ErrorAction SilentlyContinue }
    Note "ERREUR  $($_.Exception.Message)"
    exit 1
}

# 2. Toute la base (extensions et autres schémas compris)
Partie 'dump complet' {
    $f = Join-Path $Dossier "rc_full_$date.dump"
    & "$PgBin\pg_dump.exe" -h 127.0.0.1 -U postgres -d postgres -Fc -f "$f.part"
    if ($LASTEXITCODE -ne 0) { throw "pg_dump a échoué (code $LASTEXITCODE)" }
    & "$PgBin\pg_restore.exe" -l "$f.part" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "fichier illisible (code $LASTEXITCODE)" }
    Move-Item -Force "$f.part" $f
    Note "OK  $(Split-Path $f -Leaf)  ($([math]::Round((Get-Item $f).Length / 1MB, 1)) Mo)"
}

# 3. Rôles (hors base : pg_dump ne les prend pas)
Partie 'rôles' {
    $f = Join-Path $Dossier "rc_globals_$date.sql"
    & "$PgBin\pg_dumpall.exe" -h 127.0.0.1 -U postgres --globals-only -f $f
    if ($LASTEXITCODE -ne 0) { throw "pg_dumpall a échoué (code $LASTEXITCODE)" }
    Note "OK  $(Split-Path $f -Leaf)"
}

# 4. Réglages (sans node_modules), tâches planifiées, services NSSM
Partie 'réglages' {
    $tmp = Join-Path $env:TEMP "rc_config_$date"
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    foreach ($src in $Config) {
        if (-not (Test-Path $src)) { continue }
        $dest = Join-Path $tmp ($src -replace '[:\\]', '_')
        if ((Get-Item $src).PSIsContainer) {
            robocopy $src $dest /E /XD node_modules /NFL /NDL /NJH /NJS /NP | Out-Null
            if ($LASTEXITCODE -ge 8) { throw "robocopy $src (code $LASTEXITCODE)" }
        } else {
            Copy-Item $src $dest
        }
    }
    foreach ($t in 'PixelTrade-Sauvegarde', 'updateduckdns') {
        schtasks /Query /TN $t /XML 2>$null | Set-Content -Path (Join-Path $tmp "tache_$t.xml") -Encoding UTF8
    }
    $nssm = 'C:\pixeltrade\nssm.exe'
    if (Test-Path $nssm) {
        foreach ($sv in 'pixeltrade-api', 'pixeltrade-rt') {
            & $nssm dump $sv 2>$null | Set-Content -Path (Join-Path $tmp "nssm_$sv.bat") -Encoding UTF8
        }
    }
    $zip = Join-Path $Dossier "rc_config_$date.zip"
    Compress-Archive -Path "$tmp\*" -DestinationPath $zip -Force
    Remove-Item -Recurse -Force $tmp
    Note "OK  $(Split-Path $zip -Leaf)  ($([math]::Round((Get-Item $zip).Length / 1MB, 1)) Mo)"
}

# 5. Images Pokémon (miroir : les nouvelles sont ajoutées, aucune suppression)
Partie 'images Pokémon' {
    if (Test-Path 'D:\pixeltrade\pk') {
        robocopy 'D:\pixeltrade\pk' (Join-Path $Dossier 'pk') /E /XO /NFL /NDL /NJH /NJS /NP | Out-Null
        if ($LASTEXITCODE -ge 8) { throw "robocopy (code $LASTEXITCODE)" }
        Note 'OK  pk\'
    }
}

# 6. Rotation (seulement après la sauvegarde principale réussie)
Partie 'rotation' {
    $vieux = Get-ChildItem $Dossier -File -Filter 'rc_*' |
             Where-Object { $_.Extension -in '.dump', '.sql', '.zip' -and $_.LastWriteTime -lt (Get-Date).AddDays(-$Jours) }
    foreach ($f in $vieux) {
        Remove-Item $f.FullName
        Note "supprimé  $($f.Name)"
    }
}

# 7. Copie hors du disque D: (autre disque, clé, dossier synchronisé)
if ($Copie) {
    Partie 'copie' {
        New-Item -ItemType Directory -Force -Path $Copie | Out-Null
        robocopy $Dossier $Copie /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
        if ($LASTEXITCODE -ge 8) { throw "robocopy (code $LASTEXITCODE)" }
        Note "OK  copie vers $Copie"
    }
}

if ($erreurs -gt 0) { exit 1 }

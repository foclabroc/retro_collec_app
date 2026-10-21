# Contrôle de sécurité du serveur Pixel Trade / Jellyfin (lecture seule, ne modifie rien).
# Résultat dans D:\pixeltrade\checkup.txt
$out = 'D:\pixeltrade\checkup.txt'
function T($titre) { "`n=== $titre ===" }
& {
  T 'Ports en écoute hors localhost'
  Get-NetTCPConnection -State Listen | Where-Object { $_.LocalAddress -notin '127.0.0.1','::1' } |
    Sort-Object LocalPort -Unique | ForEach-Object {
      $p = (Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).ProcessName
      '{0,-6} {1,-16} {2}' -f $_.LocalPort, $_.LocalAddress, $p }
  T 'Ports UDP hors localhost'
  Get-NetUDPEndpoint | Where-Object { $_.LocalAddress -notin '127.0.0.1','::1' -and $_.LocalPort -lt 49152 } |
    Sort-Object LocalPort -Unique | ForEach-Object {
      '{0,-6} {1}' -f $_.LocalPort, (Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).ProcessName }
  T 'Profils pare-feu'
  Get-NetFirewallProfile | ForEach-Object { '{0,-8} actif={1} entrant={2}' -f $_.Name, $_.Enabled, $_.DefaultInboundAction }
  T 'Profil du réseau'
  Get-NetConnectionProfile | ForEach-Object { '{0} : {1}' -f $_.Name, $_.NetworkCategory }
  T 'Règles entrantes autorisées (actives, profil Public ou Tous)'
  Get-NetFirewallRule -Direction Inbound -Action Allow -Enabled True |
    Where-Object { $_.Profile -match 'Public|Any' } | ForEach-Object {
      $pf = $_ | Get-NetFirewallPortFilter
      if ($pf.LocalPort -and $pf.LocalPort -ne 'Any') { '{0,-50} {1} {2}' -f $_.DisplayName.Substring(0,[Math]::Min(50,$_.DisplayName.Length)), $pf.Protocol, ($pf.LocalPort -join ',') } }
  T 'Bureau à distance'
  'désactivé = ' + ((Get-ItemProperty 'HKLM:\System\CurrentControlSet\Control\Terminal Server').fDenyTSConnections -eq 1)
  T 'Partage de fichiers (SMB)'
  Get-SmbShare | Where-Object { $_.Name -notmatch '\$$' } | ForEach-Object { $_.Name + ' -> ' + $_.Path }
  'SMB1 activé = ' + (Get-SmbServerConfiguration).EnableSMB1Protocol
  T 'Windows Defender'
  $d = Get-MpComputerStatus
  'temps réel={0}  signatures={1}  dernier scan rapide={2}' -f $d.RealTimeProtectionEnabled, $d.AntivirusSignatureLastUpdated, $d.QuickScanEndTime
  T 'Dernières mises à jour Windows'
  Get-HotFix | Sort-Object InstalledOn -Descending | Select-Object -First 3 | ForEach-Object { '{0} {1}' -f $_.HotFixID, $_.InstalledOn }
  T 'Comptes Windows actifs'
  Get-LocalUser | Where-Object Enabled | ForEach-Object { '{0,-20} admin={1} mdp_requis={2}' -f $_.Name, [bool](Get-LocalGroupMember -Group 'Administrateurs' -ErrorAction SilentlyContinue | Where-Object Name -like "*\$($_.Name)"), $_.PasswordRequired }
  T 'Services du serveur'
  Get-Service Caddy, postgresql-x64-17, pixeltrade-api, pixeltrade-rt, JellyfinServer -ErrorAction SilentlyContinue |
    ForEach-Object { '{0,-20} {1,-8} {2,-10} {3}' -f $_.Name, $_.Status, $_.StartType, (Get-CimInstance Win32_Service -Filter "Name='$($_.Name)'").StartName }
  T 'Versions'
  & 'C:\caddy\caddy.exe' version
  & 'D:\pixeltrade\postgrest\postgrest.exe' --version 2>&1 | Select-Object -First 1
  & node --version
  T 'Test de l API publique'
  foreach ($u in 'https://api.foclabroc.duckdns.org/', 'https://api.foclabroc.duckdns.org/rest/v1/', 'https://api.foclabroc.duckdns.org/rest/v1/rc_players', 'https://api.foclabroc.duckdns.org/.env') {
    try { $r = Invoke-WebRequest $u -UseBasicParsing -TimeoutSec 10; "$($r.StatusCode) $u" }
    catch { "$([int]$_.Exception.Response.StatusCode) $u" } }
  $h = @{ apikey = 'sb_publishable_M1Rdee-lSEzCfq81zjYq5Q_NgJ0a35z' }
  foreach ($u in 'https://api.foclabroc.duckdns.org/rest/v1/', 'https://api.foclabroc.duckdns.org/rest/v1/rc_players?select=*', 'https://api.foclabroc.duckdns.org/rest/v1/rc_admins?select=*') {
    try { $r = Invoke-WebRequest $u -Headers $h -UseBasicParsing -TimeoutSec 10; "avec clé $($r.StatusCode) $u -> $($r.Content.Substring(0,[Math]::Min(80,$r.Content.Length)))" }
    catch { "avec clé $([int]$_.Exception.Response.StatusCode) $u" } }
  T 'DuckDNS'
  Get-Content C:\caddy\duckdns.log -Tail 2
  Get-ScheduledTask | Where-Object { $_.Actions.Arguments -match 'duckdns' } | ForEach-Object { $_.TaskName + ' : ' + $_.State + ' / dernier ' + ($_ | Get-ScheduledTaskInfo).LastRunTime }
} *>&1 | Out-File -FilePath $out -Encoding utf8
"Fini : $out"

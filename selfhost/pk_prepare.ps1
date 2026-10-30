# Série « Pokémon » : prépare les images pour le serveur maison.
# Usage : .\pk_prepare.ps1 -Zip C:\chemin\images.zip -Out D:\pixeltrade\pk
# Trie les fichiers carte-*.png par nom et les renomme 001.png, 002.png … (ordre = numéro de carte pk_NNN).
# Puis dans Caddy : handle_path /rest/v1/../pk/* n'est pas utilisé ; ajouter par exemple
#   handle /pk/* { root * D:\pixeltrade ; file_server }   (adresse = kPkBase dans lib/catalog.dart)
param([Parameter(Mandatory)][string]$Zip, [string]$Out = 'D:\pixeltrade\pk')
Add-Type -AssemblyName System.IO.Compression.FileSystem
New-Item -ItemType Directory -Force $Out | Out-Null
$z = [IO.Compression.ZipFile]::OpenRead($Zip)
$i = 0
foreach ($e in ($z.Entries | Where-Object { $_.Name -like 'carte-*' } | Sort-Object Name)) {
  $i++
  [IO.Compression.ZipFileExtensions]::ExtractToFile($e, (Join-Path $Out ('{0:000}.png' -f $i)), $true)
}
$z.Dispose()
"$i images dans $Out"

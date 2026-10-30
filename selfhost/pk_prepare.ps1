# Série « Pokémon » : prépare les images pour le serveur maison.
# Usage : .\pk_prepare.ps1 -Zip C:\chemin\images.zip -Out D:\pixeltrade\pk
# Trie les fichiers carte-*.png par nom et les renomme 001.jpg, 002.jpg … (ordre = numéro de carte pk_NNN).
# Puis dans Caddy : handle_path /rest/v1/../pk/* n'est pas utilisé ; ajouter par exemple
#   handle /pk/* { root * D:\pixeltrade ; file_server }   (adresse = kPkBase dans lib/catalog.dart)
# Les images sont réduites à -Width pixels de large (600 max) et compressées en JPEG (qualité -Quality, 85 par défaut) : 001.jpg … 185.jpg.
param([Parameter(Mandatory)][string]$Zip, [string]$Out = 'D:\pixeltrade\pk', [int]$Width = 600, [int]$Quality = 85)
Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName System.Drawing
New-Item -ItemType Directory -Force $Out | Out-Null
$z = [IO.Compression.ZipFile]::OpenRead($Zip)
$i = 0; $before = 0; $after = 0
foreach ($e in ($z.Entries | Where-Object { $_.Name -like 'carte-*' } | Sort-Object Name)) {
  $i++
  $dst = Join-Path $Out ('{0:000}.jpg' -f $i)
  $ms = New-Object IO.MemoryStream
  $s = $e.Open(); $s.CopyTo($ms); $s.Dispose()
  $before += $ms.Length
  $src = [Drawing.Image]::FromStream($ms)
  $w = [Math]::Min($Width, $src.Width)
  $h = [int][Math]::Round($src.Height * $w / $src.Width)
  $bmp = New-Object Drawing.Bitmap $w, $h, ([Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $g = [Drawing.Graphics]::FromImage($bmp)
  $g.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $g.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::HighQuality
  $g.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::HighQuality
  $g.Clear([Drawing.Color]::Black)
  $g.DrawImage($src, 0, 0, $w, $h)
  $g.Dispose()
  $codec = [Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
  $ep = New-Object Drawing.Imaging.EncoderParameters 1
  $ep.Param[0] = New-Object Drawing.Imaging.EncoderParameter ([Drawing.Imaging.Encoder]::Quality), ([long]$Quality)
  $bmp.Save($dst, $codec, $ep)
  $bmp.Dispose(); $src.Dispose(); $ms.Dispose()
  $after += (Get-Item $dst).Length
}
$z.Dispose()
'{0} images dans {1} ({2:N0} Mo -> {3:N0} Mo)' -f $i, $Out, ($before / 1MB), ($after / 1MB)

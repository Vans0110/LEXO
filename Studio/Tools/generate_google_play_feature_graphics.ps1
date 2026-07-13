param(
  [string]$OutputDir = "Virgil/App/assets/store/google_play_listing"
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

$Root = (Resolve-Path ".").Path
$OutRoot = Join-Path $Root $OutputDir
$IconPath = Join-Path $Root "Virgil/App/assets/branding/virgil_icon_master_1024.png"

if (-not (Test-Path -LiteralPath $IconPath)) {
  throw "Missing icon: $IconPath"
}

$Specs = @(
@{
    Language = "en"
    Title = "Virgil"
    Subtitle = "English stories with audio"
    Caption = "Read, listen, translate words, and review vocabulary with cards"
  },  @{
    Language = "uk"
    Title = "Virgil"
    Subtitle = "Англійські історії з озвученням"
    Caption = "Читайте, слухайте, перекладайте слова й повторюйте у картках"
  },
  @{
    Language = "ru"
    Title = "Virgil"
    Subtitle = "Английские истории с озвучкой"
    Caption = "Читайте, слушайте, переводите слова и повторяйте в карточках"
  }
)

function New-SolidBrush([int]$r, [int]$g, [int]$b) {
  return New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, $r, $g, $b))
}

function New-RoundedPath([float]$x, [float]$y, [float]$w, [float]$h, [float]$r) {
  $path = New-Object System.Drawing.Drawing2D.GraphicsPath
  $d = $r * 2
  $path.AddArc($x, $y, $d, $d, 180, 90)
  $path.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
  $path.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90)
  $path.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
  $path.CloseFigure()
  return $path
}

function Draw-Text($g, [string]$text, $font, $brush, [float]$x, [float]$y, [float]$w, [float]$h, [System.Drawing.StringAlignment]$align) {
  $fmt = New-Object System.Drawing.StringFormat
  $fmt.Alignment = $align
  $fmt.LineAlignment = [System.Drawing.StringAlignment]::Center
  $fmt.Trimming = [System.Drawing.StringTrimming]::Word
  $rect = New-Object System.Drawing.RectangleF $x, $y, $w, $h
  $g.DrawString($text, $font, $brush, $rect, $fmt)
  $fmt.Dispose()
}

foreach ($spec in $Specs) {
  $outDir = Join-Path $OutRoot $spec.Language
  New-Item -ItemType Directory -Force -Path $outDir | Out-Null

  $bmp = New-Object System.Drawing.Bitmap 1024, 500, ([System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
  $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit

  $bg = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
    (New-Object System.Drawing.Rectangle 0, 0, 1024, 500),
    [System.Drawing.Color]::FromArgb(255, 252, 246, 242),
    [System.Drawing.Color]::FromArgb(255, 242, 226, 216),
    [System.Drawing.Drawing2D.LinearGradientMode]::Horizontal
  )
  $g.FillRectangle($bg, 0, 0, 1024, 500)
  $bg.Dispose()

  $navy = New-SolidBrush 5 38 61
  $muted = New-SolidBrush 92 76 67
  $accent = New-SolidBrush 160 79 45
  $shadow = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(35, 65, 45, 36))
  $iconBg = New-SolidBrush 255 248 244

  $titleFont = New-Object System.Drawing.Font "Segoe UI", 80, ([System.Drawing.FontStyle]::Bold), ([System.Drawing.GraphicsUnit]::Pixel)
  $subtitleFont = New-Object System.Drawing.Font "Segoe UI", 42, ([System.Drawing.FontStyle]::Bold), ([System.Drawing.GraphicsUnit]::Pixel)
  $captionFont = New-Object System.Drawing.Font "Segoe UI", 28, ([System.Drawing.FontStyle]::Regular), ([System.Drawing.GraphicsUnit]::Pixel)

  $g.FillRectangle($accent, 92, 100, 150, 6)
  Draw-Text $g $spec.Title $titleFont $navy 88 122 520 98 ([System.Drawing.StringAlignment]::Near)
  Draw-Text $g $spec.Subtitle $subtitleFont $navy 92 226 610 64 ([System.Drawing.StringAlignment]::Near)
  Draw-Text $g $spec.Caption $captionFont $muted 94 308 620 86 ([System.Drawing.StringAlignment]::Near)

  $shadowPath = New-RoundedPath 736 114 206 206 46
  $g.FillPath($shadow, $shadowPath)
  $shadowPath.Dispose()
  $iconPathRound = New-RoundedPath 722 96 206 206 46
  $g.FillPath($iconBg, $iconPathRound)
  $icon = [System.Drawing.Bitmap]::FromFile($IconPath)
  $oldClip = $g.Clip
  $g.SetClip($iconPathRound)
  $g.DrawImage($icon, 722, 96, 206, 206)
  $g.Clip = $oldClip
  $icon.Dispose()
  $iconPathRound.Dispose()

  $outPath = Join-Path $outDir "feature_graphic.png"
  $bmp.Save($outPath, [System.Drawing.Imaging.ImageFormat]::Png)

  $g.Dispose()
  $bmp.Dispose()
  $navy.Dispose()
  $muted.Dispose()
  $accent.Dispose()
  $shadow.Dispose()
  $iconBg.Dispose()
  $titleFont.Dispose()
  $subtitleFont.Dispose()
  $captionFont.Dispose()
}

Write-Output "Generated feature graphics in $OutRoot"

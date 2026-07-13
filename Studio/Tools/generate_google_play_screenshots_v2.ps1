param(
  [ValidateSet("en", "uk", "ru")]
  [string]$Language = "uk",
  [string]$OutputDir = "Virgil/App/assets/store/google_play_screenshots"
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

$Root = (Resolve-Path ".").Path
$BaseOut = Join-Path $Root $OutputDir
$Out = Join-Path $BaseOut $Language
New-Item -ItemType Directory -Force -Path $Out | Out-Null

$SourceDir = "C:\Users\ivank\.codex\codex-remote-attachments\019f1861-430e-75a0-aaa0-cf084faafedd\F6531B4A-6DC4-49C6-8CC2-E73688051511"
$SourceFiles = @(Get-ChildItem -LiteralPath $SourceDir -Filter "*.jpg" | Sort-Object Name | Select-Object -ExpandProperty FullName)
if ($SourceFiles.Count -lt 7) {
  throw "Expected at least 7 source screenshots in $SourceDir, found $($SourceFiles.Count)"
}

if ($Language -eq "en") {
  $Specs = @(
    @{ File = $SourceFiles[0]; Name = "01_read_by_level.png"; Title = "ENGLISH BY LEVEL"; Subtitle = "Choose A1-C1 stories and move forward step by step." },
    @{ File = $SourceFiles[2]; Name = "02_explore_chapters.png"; Title = "TOPICS FOR EVERYDAY LIFE"; Subtitle = "Read about home, food, work, the city, and travel." },
    @{ File = $SourceFiles[3]; Name = "03_build_your_library.png"; Title = "SHORT BOOKS FOR PRACTICE"; Subtitle = "Download stories for your level and read at your own pace." },
    @{ File = $SourceFiles[4]; Name = "04_read_and_listen.png"; Title = "READ AND LISTEN TOGETHER"; Subtitle = "Follow the text, listen to narration, and adjust the speed." },
    @{ File = $SourceFiles[5]; Name = "05_tap_any_word.png"; Title = "WORD TRANSLATION IN ONE TAP"; Subtitle = "Tap a word, see its translation, and save it for review." },
    @{ File = $SourceFiles[6]; Name = "06_review_with_cards.png"; Title = "REVIEW SAVED WORDS"; Subtitle = "Practice vocabulary with cards and return to key words." }
  )
} elseif ($Language -eq "ru") {
  $Specs = @(
    @{ File = $SourceFiles[0]; Name = "01_read_by_level.png"; Title = "АНГЛИЙСКИЙ ПО УРОВНЯМ"; Subtitle = "Выбирайте истории A1-C1 и двигайтесь шаг за шагом." },
    @{ File = $SourceFiles[2]; Name = "02_explore_chapters.png"; Title = "ТЕМЫ ДЛЯ ПОВСЕДНЕВНОЙ ЖИЗНИ"; Subtitle = "Читайте про дом, еду, работу, город и путешествия." },
    @{ File = $SourceFiles[3]; Name = "03_build_your_library.png"; Title = "КОРОТКИЕ КНИГИ ДЛЯ ПРАКТИКИ"; Subtitle = "Загружайте истории своего уровня и читайте в удобном темпе." },
    @{ File = $SourceFiles[4]; Name = "04_read_and_listen.png"; Title = "ЧИТАЙТЕ И СЛУШАЙТЕ ОДНОВРЕМЕННО"; Subtitle = "Следите за текстом, слушайте озвучку и меняйте скорость." },
    @{ File = $SourceFiles[5]; Name = "05_tap_any_word.png"; Title = "ПЕРЕВОД СЛОВА ОДНИМ КАСАНИЕМ"; Subtitle = "Нажимайте на слово, смотрите перевод и сохраняйте его." },
    @{ File = $SourceFiles[6]; Name = "06_review_with_cards.png"; Title = "ПОВТОРЯЙТЕ СОХРАНЁННЫЕ СЛОВА"; Subtitle = "Тренируйте словарь в карточках и возвращайтесь к важному." }
  )
} else {
  $Specs = @(
    @{ File = $SourceFiles[0]; Name = "01_read_by_level.png"; Title = "АНГЛІЙСЬКА ЗА РІВНЯМИ"; Subtitle = "Обирайте історії A1-C1 і рухайтесь крок за кроком." },
    @{ File = $SourceFiles[2]; Name = "02_explore_chapters.png"; Title = "ТЕМИ ДЛЯ ЩОДЕННОГО ЖИТТЯ"; Subtitle = "Читайте про дім, їжу, роботу, місто й подорожі." },
    @{ File = $SourceFiles[3]; Name = "03_build_your_library.png"; Title = "КОРОТКІ КНИГИ ДЛЯ ПРАКТИКИ"; Subtitle = "Завантажуйте історії свого рівня та читайте у зручному темпі." },
    @{ File = $SourceFiles[4]; Name = "04_read_and_listen.png"; Title = "ЧИТАЙТЕ Й СЛУХАЙТЕ ОДНОЧАСНО"; Subtitle = "Слідкуйте за текстом, слухайте озвучення та змінюйте швидкість." },
    @{ File = $SourceFiles[5]; Name = "05_tap_any_word.png"; Title = "ПЕРЕКЛАД СЛОВА ОДНИМ ДОТИКОМ"; Subtitle = "Натискайте на слово, дивіться переклад і зберігайте його." },
    @{ File = $SourceFiles[6]; Name = "06_review_with_cards.png"; Title = "ПОВТОРЮЙТЕ ЗБЕРЕЖЕНІ СЛОВА"; Subtitle = "Тренуйте словник у картках і повертайтесь до важливого." }
  )
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

function Draw-CenteredText($g, [string]$text, $font, $brush, [float]$x, [float]$y, [float]$w, [float]$h) {
  $fmt = New-Object System.Drawing.StringFormat
  $fmt.Alignment = [System.Drawing.StringAlignment]::Center
  $fmt.LineAlignment = [System.Drawing.StringAlignment]::Center
  $fmt.Trimming = [System.Drawing.StringTrimming]::Word
  $rect = New-Object System.Drawing.RectangleF $x, $y, $w, $h
  $g.DrawString($text, $font, $brush, $rect, $fmt)
  $fmt.Dispose()
}

function New-SolidBrush([int]$r, [int]$g, [int]$b) {
  return New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, $r, $g, $b))
}

function Draw-PromoCard($spec) {
  $canvasW = 1080
  $canvasH = 1920
  $bmp = New-Object System.Drawing.Bitmap $canvasW, $canvasH, ([System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
  $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit

  $bg = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
    (New-Object System.Drawing.Rectangle 0, 0, $canvasW, $canvasH),
    [System.Drawing.Color]::FromArgb(255, 252, 246, 242),
    [System.Drawing.Color]::FromArgb(255, 245, 231, 222),
    [System.Drawing.Drawing2D.LinearGradientMode]::Vertical
  )
  $g.FillRectangle($bg, 0, 0, $canvasW, $canvasH)
  $bg.Dispose()

  $navy = New-SolidBrush 5 38 61
  $muted = New-SolidBrush 91 76 68
  $frameBrush = New-SolidBrush 8 36 55
  $shadowBrush1 = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(34, 65, 45, 36))
  $shadowBrush2 = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(18, 65, 45, 36))
  $accentPen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(160, 160, 79, 45)), 5

  $titleFont = New-Object System.Drawing.Font "Segoe UI", 60, ([System.Drawing.FontStyle]::Bold), ([System.Drawing.GraphicsUnit]::Pixel)
  $subtitleFont = New-Object System.Drawing.Font "Segoe UI", 32, ([System.Drawing.FontStyle]::Regular), ([System.Drawing.GraphicsUnit]::Pixel)

  $g.DrawLine($accentPen, 360, 82, 720, 82)
  Draw-CenteredText $g $spec.Title $titleFont $navy 70 118 940 150
  Draw-CenteredText $g $spec.Subtitle $subtitleFont $muted 120 270 840 96

  $phoneX = 197
  $phoneY = 420
  $phoneW = 686
  $phoneH = 1444
  $screenPad = 18
  $phoneRadius = 54
  $screenRadius = 38

  $shadowPath2 = New-RoundedPath ($phoneX + 24) ($phoneY + 34) $phoneW $phoneH $phoneRadius
  $g.FillPath($shadowBrush2, $shadowPath2)
  $shadowPath2.Dispose()
  $shadowPath1 = New-RoundedPath ($phoneX + 10) ($phoneY + 16) $phoneW $phoneH $phoneRadius
  $g.FillPath($shadowBrush1, $shadowPath1)
  $shadowPath1.Dispose()

  $phonePath = New-RoundedPath $phoneX $phoneY $phoneW $phoneH $phoneRadius
  $g.FillPath($frameBrush, $phonePath)

  $screenX = $phoneX + $screenPad
  $screenY = $phoneY + $screenPad
  $screenW = $phoneW - ($screenPad * 2)
  $screenH = $phoneH - ($screenPad * 2)
  $screenPath = New-RoundedPath $screenX $screenY $screenW $screenH $screenRadius
  $oldClip = $g.Clip
  $g.SetClip($screenPath)
  $src = [System.Drawing.Bitmap]::FromFile($spec.File)
  $g.DrawImage($src, $screenX, $screenY, $screenW, $screenH)
  $src.Dispose()
  $g.Clip = $oldClip
  $screenPath.Dispose()
  $phonePath.Dispose()

  $outPath = Join-Path $Out $spec.Name
  $bmp.Save($outPath, [System.Drawing.Imaging.ImageFormat]::Png)

  $g.Dispose()
  $bmp.Dispose()
  $navy.Dispose()
  $muted.Dispose()
  $frameBrush.Dispose()
  $shadowBrush1.Dispose()
  $shadowBrush2.Dispose()
  $accentPen.Dispose()
  $titleFont.Dispose()
  $subtitleFont.Dispose()
}

foreach ($spec in $Specs) {
  if (-not (Test-Path -LiteralPath $spec.File)) {
    throw "Missing source screenshot: $($spec.File)"
  }
  Draw-PromoCard $spec
}

$sheetW = 1620
$sheetH = 1920
$sheet = New-Object System.Drawing.Bitmap $sheetW, $sheetH, ([System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
$sg = [System.Drawing.Graphics]::FromImage($sheet)
$sg.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$sg.Clear([System.Drawing.Color]::FromArgb(255, 250, 242, 236))
$thumbW = 486
$thumbH = 864
$i = 0
foreach ($spec in $Specs) {
  $img = [System.Drawing.Bitmap]::FromFile((Join-Path $Out $spec.Name))
  $col = $i % 3
  $row = [math]::Floor($i / 3)
  $x = 30 + ($col * 530)
  $y = 50 + ($row * 910)
  $sg.DrawImage($img, $x, $y, $thumbW, $thumbH)
  $img.Dispose()
  $i += 1
}
$sheet.Save((Join-Path $Out "_preview_contact_sheet.png"), [System.Drawing.Imaging.ImageFormat]::Png)
$sg.Dispose()
$sheet.Dispose()

Write-Output "Generated Google Play screenshots in $Out"

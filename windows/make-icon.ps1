# make-icon.ps1: renders the ChatterFix logo and packs ChatterFix.ico (16/32/48/256).
# Spec coordinates are bottom-left origin on a 1024x1024 canvas; GDI+ is top-left,
# so every y here is converted as: yTop = 1024 - ySpec - height.

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$S = 1024
$bmp = New-Object System.Drawing.Bitmap $S, $S
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias

function New-RoundRectPath([float]$x, [float]$y, [float]$w, [float]$h, [float]$r) {
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = $r * 2
    $p.AddArc($x, $y, $d, $d, 180, 90)
    $p.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
    $p.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90)
    $p.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
    $p.CloseFigure()
    return $p
}

# Background: rounded square (64,64) 896x896, radius 200, vertical gradient #47526B -> #292E40
$bgRect = New-Object System.Drawing.RectangleF 64, 64, 896, 896
$bgTop = [System.Drawing.Color]::FromArgb(255, 0x47, 0x52, 0x6B)
$bgBottom = [System.Drawing.Color]::FromArgb(255, 0x29, 0x2E, 0x40)
$bgBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush($bgRect, $bgTop, $bgBottom, [System.Drawing.Drawing2D.LinearGradientMode]::Vertical)
$bgPath = New-RoundRectPath 64 64 896 896 200
$g.FillPath($bgBrush, $bgPath)

$keyBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(242, 0xF2, 0xF2, 0xF2))  # 95% opacity
$redBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 0xED, 0x54, 0x4F))
$ghostBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(115, 0xED, 0x54, 0x4F)) # 45% opacity

$keyW = 110; $keyH = 110; $keyR = 22
# Row spec-y values, bottom row first; converted to top-left y
$rowYSpec = @(390, 530, 670)
$keyXs = @(177, 317, 457, 597, 737)   # leftmost 177, gap 30
$redRowSpecY = 530; $redCol = 3       # middle row, 4th key from left

foreach ($ySpec in $rowYSpec) {
    $yTop = $S - $ySpec - $keyH
    for ($i = 0; $i -lt 5; $i++) {
        if ($ySpec -eq $redRowSpecY -and $i -eq $redCol) { continue }  # red key drawn last
        $p = New-RoundRectPath $keyXs[$i] $yTop $keyW $keyH $keyR
        $g.FillPath($keyBrush, $p)
        $p.Dispose()
    }
}

# Space bar: 450x110, centered, spec y=250
$spaceX = ($S - 450) / 2
$spaceY = $S - 250 - 110
$p = New-RoundRectPath $spaceX $spaceY 450 110 $keyR
$g.FillPath($keyBrush, $p)
$p.Dispose()

# Ghost echo behind the red key: offset +14 x, +28 y (spec coords; +y is up)
$redX = $keyXs[$redCol]
$redY = $S - $redRowSpecY - $keyH
$p = New-RoundRectPath ($redX + 14) ($redY - 28) $keyW $keyH $keyR
$g.FillPath($ghostBrush, $p)
$p.Dispose()

# The chattering key itself, solid red, on top of the ghost
$p = New-RoundRectPath $redX $redY $keyW $keyH $keyR
$g.FillPath($redBrush, $p)
$p.Dispose()

$g.Dispose()

# --- Downscale to icon sizes ---
function Get-Scaled([System.Drawing.Bitmap]$src, [int]$size) {
    $out = New-Object System.Drawing.Bitmap $size, $size
    $gg = [System.Drawing.Graphics]::FromImage($out)
    $gg.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $gg.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $gg.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $gg.DrawImage($src, 0, 0, $size, $size)
    $gg.Dispose()
    return $out
}

# BMP-format icon entry (BITMAPINFOHEADER + bottom-up BGRA + empty AND mask)
function Get-BmpEntryBytes([System.Drawing.Bitmap]$b) {
    $s = $b.Width
    $andStride = [int]([math]::Ceiling($s / 32.0) * 4)
    $ms = New-Object System.IO.MemoryStream
    $bw = New-Object System.IO.BinaryWriter $ms
    $bw.Write([int32]40); $bw.Write([int32]$s); $bw.Write([int32]($s * 2))
    $bw.Write([int16]1); $bw.Write([int16]32); $bw.Write([int32]0)
    $bw.Write([int32]($s * $s * 4 + $andStride * $s))
    $bw.Write([int32]0); $bw.Write([int32]0); $bw.Write([int32]0); $bw.Write([int32]0)
    for ($y = $s - 1; $y -ge 0; $y--) {
        for ($x = 0; $x -lt $s; $x++) {
            $c = $b.GetPixel($x, $y)
            $bw.Write([byte]$c.B); $bw.Write([byte]$c.G); $bw.Write([byte]$c.R); $bw.Write([byte]$c.A)
        }
    }
    $bw.Write((New-Object byte[] ($andStride * $s)))
    $bw.Flush()
    return ,$ms.ToArray()
}

function Get-PngEntryBytes([System.Drawing.Bitmap]$b) {
    $ms = New-Object System.IO.MemoryStream
    $b.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    return ,$ms.ToArray()
}

$sizes = @(16, 32, 48, 256)
$entries = @()
foreach ($sz in $sizes) {
    $sb = Get-Scaled $bmp $sz
    if ($sz -eq 256) { $data = Get-PngEntryBytes $sb } else { $data = Get-BmpEntryBytes $sb }
    $entries += ,@{ Size = $sz; Data = $data }
    if ($sz -eq 256) { $sb.Save((Join-Path $PSScriptRoot 'icon-preview-256.png'), [System.Drawing.Imaging.ImageFormat]::Png) }
    $sb.Dispose()
}

# --- Pack .ico ---
$icoPath = Join-Path $PSScriptRoot 'ChatterFix.ico'
$fs = [System.IO.File]::Create($icoPath)
$w = New-Object System.IO.BinaryWriter $fs
$w.Write([int16]0); $w.Write([int16]1); $w.Write([int16]$entries.Count)
$offset = 6 + 16 * $entries.Count
foreach ($e in $entries) {
    $dim = if ($e.Size -ge 256) { 0 } else { $e.Size }
    $w.Write([byte]$dim); $w.Write([byte]$dim); $w.Write([byte]0); $w.Write([byte]0)
    $w.Write([int16]1); $w.Write([int16]32)
    $w.Write([int32]$e.Data.Length); $w.Write([int32]$offset)
    $offset += $e.Data.Length
}
foreach ($e in $entries) { $w.Write($e.Data) }
$w.Flush(); $fs.Close()
$bmp.Dispose()

Write-Host "Wrote $icoPath ($([int](Get-Item $icoPath).Length) bytes)"

#requires -Version 5.1
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
$output=Join-Path (Split-Path $PSScriptRoot -Parent) 'src/WiFiProxySwitcher/assets/app.ico'
[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($output)) | Out-Null
$images=@()
foreach ($size in @(16,24,32,48,64,128,256)) {
    $b=[Drawing.Bitmap]::new($size,$size); $g=[Drawing.Graphics]::FromImage($b)
    $g.SmoothingMode=[Drawing.Drawing2D.SmoothingMode]::AntiAlias; $g.ScaleTransform($size/32.0,$size/32.0)
    $brush=[Drawing.SolidBrush]::new([Drawing.Color]::FromArgb(0,103,192)); $pen=[Drawing.Pen]::new([Drawing.Color]::White,2.4)
    $pen.StartCap=[Drawing.Drawing2D.LineCap]::Round; $pen.EndCap=$pen.StartCap
    try { $g.FillEllipse($brush,1,1,30,30); $g.DrawArc($pen,6,8,20,18,220,100); $g.DrawArc($pen,10,13,12,11,220,100); $g.FillEllipse([Drawing.Brushes]::White,14,22,4,4); $s=[IO.MemoryStream]::new(); try { $b.Save($s,[Drawing.Imaging.ImageFormat]::Png); $images+=,@{Size=$size;Bytes=$s.ToArray()} } finally { $s.Dispose() } }
    finally { $pen.Dispose();$brush.Dispose();$g.Dispose();$b.Dispose() }
}
$stream=[IO.File]::Create($output); $writer=[IO.BinaryWriter]::new($stream)
try {
    $writer.Write([uint16]0);$writer.Write([uint16]1);$writer.Write([uint16]$images.Count);$offset=6+16*$images.Count
    foreach ($image in $images) { $dimension=$image.Size; if($dimension -eq 256){$dimension=0};$writer.Write([byte]$dimension);$writer.Write([byte]$dimension);$writer.Write([uint16]0);$writer.Write([uint16]1);$writer.Write([uint16]32);$writer.Write([uint32]$image.Bytes.Length);$writer.Write([uint32]$offset);$offset+=$image.Bytes.Length }
    foreach ($image in $images) { $writer.Write([byte[]]$image.Bytes) }
} finally {$writer.Dispose();$stream.Dispose()}

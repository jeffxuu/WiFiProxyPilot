#requires -Version 5.1
[CmdletBinding()]
param([string]$OutputDirectory)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
if (-not $OutputDirectory) { $OutputDirectory = Join-Path (Split-Path $PSScriptRoot -Parent) 'src/WiFiProxySwitcher/assets' }
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
[IO.Directory]::CreateDirectory($OutputDirectory) | Out-Null
$original = Join-Path (Split-Path $PSScriptRoot -Parent) 'src/WiFiProxySwitcher/assets/pilot.svg'
$source = [IO.File]::ReadAllText($original)
$sizes = @(16,20,24,32,48,64,128,256)
$badges = [ordered]@{
    app = ''
    monitoring = '<circle cx="50" cy="50" r="10" fill="#2A9879" stroke="#F4F8FF" stroke-width="2"/><path d="M47 45 L54 50 L47 55 Z" fill="#FFFFFF"/>'
    direct = '<circle cx="50" cy="50" r="10" fill="#287CC0" stroke="#F4F8FF" stroke-width="2"/><path d="M44 50 L56 50 M52 46 L56 50 L52 54" fill="none" stroke="#FFFFFF" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"/>'
    paused = '<circle cx="50" cy="50" r="10" fill="#66758B" stroke="#F4F8FF" stroke-width="2"/><path d="M47 46 L47 54 M53 46 L53 54" fill="none" stroke="#FFFFFF" stroke-width="3" stroke-linecap="round"/>'
    attention = '<circle cx="50" cy="50" r="10" fill="#E4AE36" stroke="#F4F8FF" stroke-width="2"/><path d="M50 44 L50 50" fill="none" stroke="#16365F" stroke-width="3" stroke-linecap="round"/><circle cx="50" cy="54.5" r="1.5" fill="#16365F"/>'
}

function Number([Xml.XmlElement]$Element, [string]$Name, [double]$Default = 0) {
    if ($Element.HasAttribute($Name)) { return [double]::Parse($Element.GetAttribute($Name), [Globalization.CultureInfo]::InvariantCulture) }
    return $Default
}
function SvgPath([string]$Data) {
    # The exporter supports our vector source's absolute M/L/C/Z paths.
    # Unsupported commands fail instead of silently producing an incorrect icon.
    $tokens = [regex]::Matches($Data, '[A-Za-z]|[-+]?(?:\d*\.\d+|\d+)(?:[eE][-+]?\d+)?')
    $path = [Drawing.Drawing2D.GraphicsPath]::new()
    $point = [Drawing.PointF]::new(0,0); $start = $point; $i = 0; $command = ''
    while ($i -lt $tokens.Count) {
        if ($tokens[$i].Value -match '^[A-Za-z]$') { $command = $tokens[$i].Value; $i++ }
        $count = switch ($command) { 'M' {2}; 'L' {2}; 'C' {6}; 'Z' {0}; default { throw "Unsupported SVG path command $command" } }
        if ($command -eq 'Z') { $path.CloseFigure(); $point=$start; $command=''; continue }
        if ($i + $count -gt $tokens.Count) { throw 'Incomplete SVG path' }
        $values = @(for($j=0; $j -lt $count; $j++) { [single]::Parse($tokens[$i+$j].Value,[Globalization.CultureInfo]::InvariantCulture) }); $i += $count
        $next = [Drawing.PointF]::new($values[$count-2],$values[$count-1])
        switch ($command) {
            'M' { $path.StartFigure(); $point=$next; $start=$next; $command='L' }
            'L' { $path.AddLine($point,$next); $point=$next }
            'C' { $path.AddBezier($point,[Drawing.PointF]::new($values[0],$values[1]),[Drawing.PointF]::new($values[2],$values[3]),$next); $point=$next }
        }
    }
    return ,$path
}
function RenderSvg([string]$Text, [int]$Size) {
    [xml]$svg = $Text
    # Fourfold supersampling makes the signal and route legible at the tray's 16 px.
    $bitmap = [Drawing.Bitmap]::new($Size*4,$Size*4,[Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.ScaleTransform($Size/16.0,$Size/16.0)
    try {
        foreach($element in $svg.DocumentElement.ChildNodes) {
            if($element -isnot [Xml.XmlElement] -or $element.LocalName -in @('title','desc')) { continue }
            $shape = [Drawing.Drawing2D.GraphicsPath]::new()
            try {
                switch($element.LocalName) {
                    'rect' {
                        $x=Number $element 'x'; $y=Number $element 'y'; $w=Number $element 'width'; $h=Number $element 'height'; $r=Number $element 'rx'
                        if($r -eq 0) { $shape.AddRectangle([Drawing.RectangleF]::new($x,$y,$w,$h)) }
                        else { $d=$r*2; $shape.AddArc($x,$y,$d,$d,180,90); $shape.AddArc($x+$w-$d,$y,$d,$d,270,90); $shape.AddArc($x+$w-$d,$y+$h-$d,$d,$d,0,90); $shape.AddArc($x,$y+$h-$d,$d,$d,90,90); $shape.CloseFigure() }
                    }
                    'circle' { $r=Number $element 'r'; $shape.AddEllipse((Number $element 'cx')-$r,(Number $element 'cy')-$r,$r*2,$r*2) }
                    'path' { $shape.Dispose(); $shape = SvgPath $element.GetAttribute('d') }
                    default { throw "Unsupported SVG element $($element.LocalName)" }
                }
                $fill=$element.GetAttribute('fill'); $stroke=$element.GetAttribute('stroke')
                if($fill -and $fill -ne 'none') { $brush=[Drawing.SolidBrush]::new([Drawing.ColorTranslator]::FromHtml($fill)); try{$graphics.FillPath($brush,$shape)}finally{$brush.Dispose()} }
                if($stroke -and $stroke -ne 'none') {
                    $pen=[Drawing.Pen]::new([Drawing.ColorTranslator]::FromHtml($stroke),(Number $element 'stroke-width' 1))
                    if($element.GetAttribute('stroke-linecap') -eq 'round') { $pen.StartCap=[Drawing.Drawing2D.LineCap]::Round; $pen.EndCap=$pen.StartCap }
                    $pen.LineJoin=[Drawing.Drawing2D.LineJoin]::Round
                    try{$graphics.DrawPath($pen,$shape)}finally{$pen.Dispose()}
                }
            } finally { $shape.Dispose() }
        }
        $reduced=[Drawing.Bitmap]::new($Size,$Size,[Drawing.Imaging.PixelFormat]::Format32bppArgb); $g=[Drawing.Graphics]::FromImage($reduced)
        try { $g.InterpolationMode=[Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic; $g.PixelOffsetMode=[Drawing.Drawing2D.PixelOffsetMode]::HighQuality; $g.DrawImage($bitmap,[Drawing.Rectangle]::new(0,0,$Size,$Size)); $stream=[IO.MemoryStream]::new(); try{$reduced.Save($stream,[Drawing.Imaging.ImageFormat]::Png); return ,$stream.ToArray()}finally{$stream.Dispose()} }
        finally{$g.Dispose();$reduced.Dispose()}
    } finally { $graphics.Dispose(); $bitmap.Dispose() }
}
foreach($name in $badges.Keys) {
    $svg = $source.Replace('</svg>', $badges[$name] + '</svg>')
    if($name -ne 'app') { [IO.File]::WriteAllText((Join-Path $OutputDirectory ($name+'.svg')),$svg,[Text.UTF8Encoding]::new($false)) }
    $images=@(foreach($size in $sizes) { $bytes=RenderSvg $svg $size; [IO.File]::WriteAllBytes((Join-Path $OutputDirectory ($name+'-'+$size+'.png')),$bytes); @{ Size=$size; Bytes=$bytes } })
    $output = Join-Path $OutputDirectory ($name+'.ico'); $stream=[IO.File]::Create($output); $writer=[IO.BinaryWriter]::new($stream)
    try {
        $writer.Write([uint16]0);$writer.Write([uint16]1);$writer.Write([uint16]$images.Count);$offset=6+16*$images.Count
        foreach($image in $images) { $dimension=$image.Size; if($dimension -eq 256){$dimension=0}; $writer.Write([byte]$dimension);$writer.Write([byte]$dimension);$writer.Write([uint16]0);$writer.Write([uint16]1);$writer.Write([uint16]32);$writer.Write([uint32]$image.Bytes.Length);$writer.Write([uint32]$offset);$offset+=$image.Bytes.Length }
        foreach($image in $images) { $writer.Write([byte[]]$image.Bytes) }
    } finally { $writer.Dispose();$stream.Dispose() }
    Write-Output "$name ICO: $($sizes -join ', ') px"
}

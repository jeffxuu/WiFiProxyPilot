#requires -Version 5.1
[CmdletBinding()]
param([string]$Destination='')
$ErrorActionPreference='Stop'
if (-not $Destination) { $Destination=Join-Path $PSScriptRoot 'generated/inno-7.1.0' }
# Transport is an immutable NuGet package of upstream tools. No compiler installation,
# registry entry or shortcut is created on the build computer. Verify upstream signatures.
$version='7.1.0'
$packageHash='AAD15C662593C6F5656457A5C001F4591BABD72820CACF63F9706D4AF5D93B75'
$url='https://api.nuget.org/v3-flatcontainer/tools.innosetup/7.1.0/tools.innosetup.7.1.0.nupkg'
[IO.Directory]::CreateDirectory($Destination) | Out-Null
$package=Join-Path $Destination 'compiler.nupkg'
if (-not (Test-Path -LiteralPath $package)) { Invoke-WebRequest -Uri $url -OutFile $package -UseBasicParsing }
if ((Get-FileHash -LiteralPath $package -Algorithm SHA256).Hash -cne $packageHash) { throw 'Pinned Inno Setup package checksum mismatch' }
Add-Type -AssemblyName System.IO.Compression.FileSystem
$tools=Join-Path $Destination 'package/tools'
if (-not (Test-Path -LiteralPath (Join-Path $tools 'ISCC.exe'))) { [IO.Compression.ZipFile]::ExtractToDirectory($package,(Join-Path $Destination 'package')) }
foreach ($name in @('ISCC.exe','ISCmplr.dll','ISPP.dll','ISSigTool.exe')) {
    $path=Join-Path $tools $name
    $signature=Get-AuthenticodeSignature -LiteralPath $path
    if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch '(^|, )O=Pyrsys B\.V\.(,|$)') { throw ('Inno Setup upstream signature invalid: '+$name) }
}
$compiler=Join-Path $tools 'ISCC.exe'
$output=& $compiler '--version' 2>&1 | Out-String
if ($output.Trim() -ne $version) { throw ('Unexpected Inno Setup compiler version: '+$output.Trim()) }
$record=[ordered]@{Version=$version;PackageUrl=$url;PackageSHA256=$packageHash;Upstream='https://jrsoftware.org/isdl.php';Signature='Valid; Pyrsys B.V.';CompilerSHA256=(Get-FileHash -LiteralPath $compiler -Algorithm SHA256).Hash}
[IO.File]::WriteAllText((Join-Path $Destination 'dependency.json'),($record | ConvertTo-Json),[Text.UTF8Encoding]::new($false))
Write-Output $compiler

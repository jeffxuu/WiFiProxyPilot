#requires -Version 5.1
[CmdletBinding()]
param([string]$Dotnet='dotnet',[switch]$SkipTests,[string]$InnoCompiler='')
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
. (Join-Path $repo 'lib/Lifecycle.ps1')
& (Join-Path $repo 'tools/Generate-Icon.ps1')
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$generated=Join-Path $PSScriptRoot 'generated'; [IO.Directory]::CreateDirectory($generated) | Out-Null
[IO.File]::WriteAllText((Join-Path $generated 'NativeReader.cs'),("#nullable disable"+[Environment]::NewLine+[IO.File]::ReadAllText((Join-Path $repo 'lib/Native.cs'))),[Text.UTF8Encoding]::new($false))
$zipPath=Join-Path $generated 'payload.zip'; if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
$hashes=[ordered]@{}
$stream=[IO.File]::Open($zipPath,[IO.FileMode]::CreateNew)
$zip=[IO.Compression.ZipArchive]::new($stream,[IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($name in @(Get-DistributionFiles | Sort-Object)) {
        $path=Join-Path $repo $name
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw ('安装资源缺失: '+$name) }
        $hashes[$name]=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
        $entry=$zip.CreateEntry($name,[IO.Compression.CompressionLevel]::Optimal); $entry.LastWriteTime=[DateTimeOffset]::new(2026,1,1,0,0,0,[TimeSpan]::Zero)
        $sourceStream=[IO.File]::OpenRead($path); $destinationStream=$entry.Open()
        try { $sourceStream.CopyTo($destinationStream) } finally { $sourceStream.Dispose(); $destinationStream.Dispose() }
    }
} finally { $zip.Dispose(); $stream.Dispose() }
[IO.File]::WriteAllText((Join-Path $generated 'payload.manifest.json'),($hashes | ConvertTo-Json),[Text.UTF8Encoding]::new($false))
if (-not $SkipTests) {
    & $Dotnet run --project (Join-Path $repo 'tests/Launcher.Tests/Launcher.Tests.csproj') --configuration Release -- (Join-Path $generated 'launcher-results.json')
    if ($LASTEXITCODE) { throw 'Launcher tests failed' }
}
$out=Join-Path $repo 'publish/self-contained/win-x64'
& $Dotnet publish (Join-Path $repo 'src/WiFiProxySwitcher/WiFiProxySwitcher.csproj') --configuration Release --runtime win-x64 --self-contained true --output $out
if ($LASTEXITCODE) { throw 'EXE publish failed' }
$exe=Join-Path $out 'WiFiProxySwitcher.exe'; if (-not (Test-Path -LiteralPath $exe)) { throw 'Missing published application EXE' }
$dist=Join-Path $PSScriptRoot 'dist'; [IO.Directory]::CreateDirectory($dist) | Out-Null
foreach ($oldName in @('WiFiProxySwitcher.exe','WiFiProxySwitcher.zip')) {
    $oldOutput=[IO.Path]::GetFullPath((Join-Path $dist $oldName))
    if (-not $oldOutput.StartsWith(([IO.Path]::GetFullPath($dist).TrimEnd('\')+'\'),[StringComparison]::OrdinalIgnoreCase)) { throw 'Release output cleanup escaped dist' }
    if (Test-Path -LiteralPath $oldOutput -PathType Leaf) {
        $oldArchive=Join-Path $generated 'legacy-build-output'; [IO.Directory]::CreateDirectory($oldArchive) | Out-Null
        $oldDestination=[IO.Path]::GetFullPath((Join-Path $oldArchive ((Get-FileHash -LiteralPath $oldOutput).Hash.Substring(0,12)+'-'+$oldName)))
        if (-not $oldDestination.StartsWith(([IO.Path]::GetFullPath($generated).TrimEnd('\')+'\'),[StringComparison]::OrdinalIgnoreCase)) { throw 'Legacy output archive escaped generated' }
        Move-Item -LiteralPath $oldOutput -Destination $oldDestination -Force
    }
}
# A regular publish is installed to avoid single-file runtime unpacking on every cache-cold start.
$stage=Join-Path $generated 'installer-stage'; [IO.Directory]::CreateDirectory($stage) | Out-Null
& $Dotnet publish (Join-Path $repo 'src/WiFiProxySwitcher/WiFiProxySwitcher.csproj') --configuration Release --runtime win-x64 --self-contained true --output $stage '-p:PublishSingleFile=false'
if ($LASTEXITCODE) { throw 'Installed application publish failed' }
Copy-Item -LiteralPath (Join-Path $stage 'WiFiProxySwitcher.exe') -Destination (Join-Path $stage 'WiFiProxyPilot.exe') -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'InstallerLifecycle.ps1') -Destination $stage -Force
$engine=Join-Path $stage 'engine'; [IO.Directory]::CreateDirectory($engine) | Out-Null
foreach ($name in Get-DistributionFiles) {
    $target=Join-Path $engine $name; [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target)) | Out-Null
    Copy-Item -LiteralPath (Join-Path $repo $name) -Destination $target -Force
}
$installFiles=@(Get-ChildItem -LiteralPath $stage -File -Recurse | Where-Object { $_.Name -notin @('WiFiProxySwitcher.exe','installer-files.json') } | ForEach-Object {
    [pscustomobject]@{Path=$_.FullName.Substring($stage.Length+1).Replace('\','/');Hash=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash}
})
[IO.File]::WriteAllText((Join-Path $stage 'installer-files.json'),([pscustomobject]@{Version='3.3.0-beta.1';Files=$installFiles} | ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
if (-not $InnoCompiler) { $InnoCompiler=& (Join-Path $PSScriptRoot 'Get-InnoCompiler.ps1') }
& $InnoCompiler ('/DSourceDir='+$stage) ('/DOutputPath='+$dist) (Join-Path $PSScriptRoot 'WiFiProxyPilot.iss')
if ($LASTEXITCODE -or -not (Test-Path -LiteralPath (Join-Path $dist 'WiFiProxyPilot-Setup-x64.exe'))) { throw 'Setup EXE compilation failed' }
$archive=Join-Path $dist 'WiFiProxyPilot-Portable-x64.zip'; if (Test-Path -LiteralPath $archive) { Remove-Item -LiteralPath $archive -Force }
$s=[IO.File]::Open($archive,[IO.FileMode]::CreateNew); $z=[IO.Compression.ZipArchive]::new($s,[IO.Compression.ZipArchiveMode]::Create)
try {
    $documentation=@('LICENSE','CONTRIBUTING.md','SECURITY.md')
    $documentation+=@(Get-ChildItem -LiteralPath $repo -Filter 'README*.md' | ForEach-Object Name)
    $documentation+=@(Get-DistributionFiles | Where-Object { $_ -like 'docs/*' })
    $documentation+=@('docs/GITHUB_DELIVERY.md','docs/evidence/v32-preview-performance.json')
    $documentation+=@(Get-ChildItem -LiteralPath (Join-Path $repo 'docs/evidence') -Filter 'github-delivery-*.json' | ForEach-Object { 'docs/evidence/'+$_.Name })
    $documentation+=@(Get-ChildItem -LiteralPath (Join-Path $repo 'docs/images') -File | ForEach-Object { 'docs/images/'+$_.Name })
    $pairs=@([pscustomobject]@{Path=$exe;Name='WiFiProxyPilot.exe'})
    foreach($name in @($documentation | Sort-Object -Unique)) { $pairs+=[pscustomobject]@{Path=(Join-Path $repo $name);Name=$name} }
    foreach ($pair in $pairs) {
        [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($z,$pair.Path,$pair.Name,[IO.Compression.CompressionLevel]::Optimal) | Out-Null
    }
} finally { $z.Dispose(); $s.Dispose() }
$lines=@(); foreach ($name in @('WiFiProxyPilot-Setup-x64.exe','WiFiProxyPilot-Portable-x64.zip')) { $lines += ((Get-FileHash -LiteralPath (Join-Path $dist $name) -Algorithm SHA256).Hash.ToLowerInvariant()+'  '+$name) }
[IO.File]::WriteAllText((Join-Path $dist 'SHA256.txt'),(($lines -join "`n")+"`n"),[Text.UTF8Encoding]::new($false))
$build=[ordered]@{Version='3.3.0-beta.1';TimeUtc=[DateTimeOffset]::UtcNow.ToString('o');Compiler='Inno Setup 7.1.0';ProgramName='WiFiProxyPilot.exe';InstallOwner='Inno';EngineOwner='WiFiProxySwitcher-v1';InstalledRuntime='unbundled self-contained';PortableRuntime='single-file self-contained';Checksums=$lines}
[IO.File]::WriteAllText((Join-Path $generated 'build-record.json'),($build | ConvertTo-Json -Depth 4),[Text.UTF8Encoding]::new($false))
Write-Output ('发布产物: '+$dist)

#requires -Version 5.1
[CmdletBinding()]
param([string]$Exe = '', [string]$OutputDirectory = '')
$ErrorActionPreference='Stop'
if (-not $Exe) { $Exe=Join-Path (Split-Path $PSScriptRoot -Parent) 'publish/self-contained/win-x64/WiFiProxySwitcher.exe' }
if (-not $OutputDirectory) { $OutputDirectory=Join-Path ([IO.Path]::GetTempPath()) ('WiFiPilot-preview-'+[Guid]::NewGuid().ToString('N')) }
$exePath=[IO.Path]::GetFullPath($Exe);$previewRoot=[IO.Path]::GetFullPath($OutputDirectory)
if (-not (Test-Path -LiteralPath $exePath -PathType Leaf)) { throw '请先运行 release/Build.ps1 构建 EXE。' }
[IO.Directory]::CreateDirectory($previewRoot) | Out-Null
$reportPath=Join-Path $previewRoot 'preview.json'
# This is a user-invoked interactive preview; a visible window is intentional.
Start-Process -FilePath $exePath -ArgumentList @('/preview','/output',('"'+$reportPath+'"')) | Out-Null
Write-Output ('隔离预览目录：'+$previewRoot)

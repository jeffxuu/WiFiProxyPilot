#requires -Version 5.1
[CmdletBinding()]
param([string]$ResultPath='')
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
$testOutput=$ResultPath
. (Join-Path $repo 'release/InstallerLifecycle.ps1') -EngineSource $repo -ImportOnly
$results=[Collections.Generic.List[object]]::new()
function Check([bool]$Value,[string]$Message='Assertion failed') { if (-not $Value) { throw $Message } }
function Case([string]$Name,[scriptblock]$Body) {
    try { & $Body; $results.Add([pscustomobject]@{Name=$Name;Passed=$true;Error=''}); Write-Host ('PASS '+$Name) }
    catch { $results.Add([pscustomobject]@{Name=$Name;Passed=$false;Error=$_.Exception.Message;Stack=$_.ScriptStackTrace}); Write-Host ('FAIL '+$Name+': '+$_.Exception.Message) }
}
function New-Fixture {
    $base=Join-Path ([IO.Path]::GetTempPath()) ('pilot-installer-'+[Guid]::NewGuid().ToString('N'))
    $app=Join-Path $base '程序 有空格'; $data=Join-Path $base 'engine-data'
    [IO.Directory]::CreateDirectory($app) | Out-Null; [IO.Directory]::CreateDirectory((Join-Path $data 'state')) | Out-Null
    [IO.File]::WriteAllText((Join-Path $app 'WiFiProxyPilot.exe'),'MZ isolated test fixture')
    [IO.File]::WriteAllText((Join-Path $app 'unins000.exe'),'MZ isolated uninstaller fixture')
    Write-JsonAtomic (Join-Path $app 'installer-files.json') ([pscustomobject]@{Files=@([pscustomobject]@{Path='WiFiProxyPilot.exe';Hash=(Get-FileHash -LiteralPath (Join-Path $app 'WiFiProxyPilot.exe')).Hash})})
    $owner=[pscustomobject]@{Product='WiFiProxyPilot-Inno-v1';OwnerSid='S-1-5-21-1-2-3-1001';AppDir=$app;Version='3.3.0-beta.1';AppId='{15F7908C-5C54-4D45-9343-1973BFEA3B47}';ReceiptSha256=(Get-FileHash -LiteralPath (Join-Path $app 'installer-files.json')).Hash;UninstallerSha256=(Get-FileHash -LiteralPath (Join-Path $app 'unins000.exe')).Hash}
    Write-JsonAtomic (Join-Path $app 'installer-owned.json') $owner
    $script:fixture=@{Base=$base;App=$app;Data=$data;Owner=$owner;Stops=0;GuiStops=0;Writes=0}
}
function Remove-Fixture {
    $full=[IO.Path]::GetFullPath($script:fixture.Base)
    $temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
    if (-not $full.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase) -or $full -notmatch 'pilot-installer-[0-9a-f]{32}$') { throw 'Unsafe test cleanup path' }
    Remove-Item -LiteralPath $full -Recurse -Force
}
Case 'Installer ownership validates current SID and full application path' {
    New-Fixture
    function Get-UserSid { 'S-1-5-21-1-2-3-1001' }
    try {
        Check ((Assert-InstallerDesktopDirectory $fixture.App).AppDir -ceq $fixture.App)
        $fixture.Owner.OwnerSid='S-1-5-21-1-2-3-2002'; Write-JsonAtomic (Join-Path $fixture.App 'installer-owned.json') $fixture.Owner
        $caught=$false; try { Assert-InstallerDesktopDirectory $fixture.App | Out-Null } catch { $caught=$true }; Check $caught
    } finally { Remove-Fixture }
}
Case 'Installer rejects engine-data directory as program install target' {
    New-Fixture
    function Get-InstalledRoot { $fixture.Data }
    try {
        foreach ($path in @($fixture.Data,(Join-Path $fixture.Data 'nested'))) {
            $caught=$false; try { Assert-InstallerAppPath $path | Out-Null } catch { $caught=$true }; Check $caught
        }
        Check ((Assert-InstallerAppPath $fixture.App) -ceq $fixture.App)
    } finally { Remove-Fixture }
}
Case 'Modified application, managed DLL, receipt or uninstaller is refused before execution' {
    New-Fixture
    function Get-UserSid { 'S-1-5-21-1-2-3-1001' }
    try {
        $library=Join-Path $fixture.App 'WiFiProxySwitcher.dll'; [IO.File]::WriteAllText($library,'original managed assembly')
        $receipt=Get-Content -LiteralPath (Join-Path $fixture.App 'installer-files.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        $receipt.Files+=([pscustomobject]@{Path='WiFiProxySwitcher.dll';Hash=(Get-FileHash -LiteralPath $library).Hash})
        Write-JsonAtomic (Join-Path $fixture.App 'installer-files.json') $receipt
        $fixture.Owner.ReceiptSha256=(Get-FileHash -LiteralPath (Join-Path $fixture.App 'installer-files.json')).Hash
        Write-JsonAtomic (Join-Path $fixture.App 'installer-owned.json') $fixture.Owner
        Assert-InstallerDesktopDirectory $fixture.App | Out-Null
        foreach ($relative in @('WiFiProxyPilot.exe','WiFiProxySwitcher.dll','installer-files.json','unins000.exe')) {
            $path=Join-Path $fixture.App $relative; $before=[IO.File]::ReadAllBytes($path)
            [IO.File]::WriteAllText($path,'untrusted modified content')
            $code=''; try { Assert-InstallerDesktopDirectory $fixture.App | Out-Null } catch { $code=$_.Exception.Data['WiFiProxyCode'] }
            Check ($code -ceq 'InstallerAppModified') ('No stable integrity refusal for '+$relative)
            Check ([IO.File]::ReadAllText($path) -ceq 'untrusted modified content') 'Refusal must preserve modified files'
            [IO.File]::WriteAllBytes($path,$before)
        }
    } finally { Remove-Fixture }
}
Case 'Restore conflict inspection is read-only and does not stop watcher or GUI' {
    New-Fixture
    function Get-ManualSnapshot { [pscustomobject]@{id='manual-user-edit'} }
    function Read-OriginalProxy { [pscustomobject]@{id='original'} }
    function Test-RestoreAllowed($Current,$Prior) { return $Current.id -ceq $Prior.id }
    function Stop-OwnedWatcher { throw 'Must not stop watcher during inspection' }
    function Stop-InstallerGui { throw 'Must not stop GUI during inspection' }
    try {
        Write-JsonAtomic (Join-Path $fixture.Data 'state/last-applied.json') ([pscustomobject]@{id='pilot-last-write'})
        $before=@(Get-ChildItem -LiteralPath $fixture.Data -File -Recurse | ForEach-Object { (Get-FileHash -LiteralPath $_.FullName).Hash }) -join ','
        Check (Test-InstallerRestoreConflict ([pscustomobject]@{Root=$fixture.Data}))
        $after=@(Get-ChildItem -LiteralPath $fixture.Data -File -Recurse | ForEach-Object { (Get-FileHash -LiteralPath $_.FullName).Hash }) -join ','
        Check ($before -ceq $after)
    } finally { Remove-Fixture }
}
Case 'Canceled uninstall leaves GUI, watcher and every ownership file unchanged' {
    New-Fixture
    function Assert-InstallerDesktopDirectory { $fixture.Owner }
    function Get-InstallerEngine { $null }
    function Stop-InstallerGui { $fixture.GuiStops++ }
    function Uninstall-Product { $fixture.Stops++ }
    try {
        $marker=Get-FileHash -LiteralPath (Join-Path $fixture.App 'installer-owned.json')
        $caught=$false; try { Invoke-InstallerUninstall $fixture.App 'Cancel' $false | Out-Null } catch { $caught=$true }
        Check ($caught -and $fixture.GuiStops -eq 0 -and $fixture.Stops -eq 0)
        Check ((Get-FileHash -LiteralPath $marker.Path).Hash -ceq $marker.Hash)
    } finally { Remove-Fixture }
}
Case 'Missing upgrade payload fails before GUI shutdown, watcher changes or registration' {
    New-Fixture
    function Get-InstalledRoot { '' }
    function Read-InstallerDesktop { $null }
    function Get-InstallerEngine { $null }
    function Stop-InstallerGui { $fixture.GuiStops++ }
    try {
        Remove-Item -LiteralPath (Join-Path $fixture.App 'WiFiProxyPilot.exe') -Force
        Remove-Item -LiteralPath (Join-Path $fixture.App 'installer-owned.json') -Force
        $EngineSource=Join-Path $fixture.Base 'missing-engine'
        $caught=$false; try { Invoke-InstallerPrepare $fixture.App | Out-Null } catch { $caught=$true }
        Check ($caught -and $fixture.GuiStops -eq 0 -and -not (Test-Path -LiteralPath (Join-Path $fixture.App 'installer-owned.json')))
    } finally { Remove-Fixture }
}
Case 'Interrupted first Setup retries only SID-owned hash-matching files' {
    New-Fixture
    function Get-UserSid { 'S-1-5-21-1-2-3-1001' }
    try {
        Remove-Item -LiteralPath (Join-Path $fixture.App 'installer-owned.json') -Force
        $exe=Join-Path $fixture.App 'WiFiProxyPilot.exe'
        $pending=[pscustomobject]@{Product='WiFiProxyPilot-Inno-Pending-v1';OwnerSid=(Get-UserSid);AppDir=$fixture.App;AppId='{15F7908C-5C54-4D45-9343-1973BFEA3B47}';Files=@([pscustomobject]@{Path='WiFiProxyPilot.exe';Hash=(Get-FileHash -LiteralPath $exe).Hash})}
        Write-JsonAtomic (Join-Path $fixture.App 'installer-pending.json') $pending
        Check (Assert-InstallerPending $fixture.App)
        [IO.File]::WriteAllText((Join-Path $fixture.App 'user-owned.txt'),'do not delete')
        $caught=$false; try { Assert-InstallerPending $fixture.App | Out-Null } catch { $caught=$true }; Check $caught
        Check ([IO.File]::ReadAllText((Join-Path $fixture.App 'user-owned.txt')) -ceq 'do not delete')
        Remove-Item -LiteralPath (Join-Path $fixture.App 'user-owned.txt') -Force
        [IO.File]::WriteAllText($exe,'changed by user')
        $caught=$false; try { Assert-InstallerPending $fixture.App | Out-Null } catch { $caught=$true }; Check $caught
    } finally { Remove-Fixture }
}
Case 'Retain user data copies exact modified config, original backup and owned logs' {
    New-Fixture
    function Get-InstallerRetentionRoot { Join-Path $fixture.Base 'retained' }
    function Get-InstallerUiDataRoot { Join-Path $fixture.Base 'ui-data' }
    try {
        [IO.Directory]::CreateDirectory((Get-InstallerUiDataRoot)) | Out-Null
        [IO.File]::WriteAllText((Join-Path (Get-InstallerUiDataRoot) 'preferences.json'),'{"Language":"en-US"}')
        $files=@('config.json','config.json.previous','state/proxy-before-install.json','logs/watcher.jsonl','logs/watcher.jsonl.1')
        foreach ($name in $files) {
            $path=Join-Path $fixture.Data $name
            [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path)) | Out-Null
            [IO.File]::WriteAllBytes($path,[Text.UTF8Encoding]::new($true).GetBytes('user modified '+$name))
        }
        [IO.File]::WriteAllText((Join-Path $fixture.Data 'logs/user-private.txt'),'unknown user content')
        $retained=Save-InstallerUserData ([pscustomobject]@{Root=$fixture.Data}) $false
        foreach ($name in $files) {
            Check ((Get-FileHash -LiteralPath (Join-Path $fixture.Data $name)).Hash -ceq (Get-FileHash -LiteralPath (Join-Path $retained $name)).Hash) ('Retention copy mismatch '+$name)
        }
        Check (-not (Test-Path -LiteralPath (Join-Path $retained 'logs/user-private.txt')))
        Check (Test-Path -LiteralPath (Join-Path $fixture.Data 'logs/user-private.txt'))
        Check ((Get-FileHash -LiteralPath (Join-Path (Get-InstallerUiDataRoot) 'preferences.json')).Hash -ceq (Get-FileHash -LiteralPath (Join-Path $retained 'ui/preferences.json')).Hash)
    } finally { Remove-Fixture }
}
Case 'Explicit delete removes only selected configuration files and leaves root and unknown data' {
    New-Fixture
    function Get-InstallerRetentionRoot { Join-Path $fixture.Base 'retained' }
    function Get-InstallerUiDataRoot { Join-Path $fixture.Base 'ui-data' }
    try {
        [IO.Directory]::CreateDirectory((Get-InstallerUiDataRoot)) | Out-Null
        [IO.File]::WriteAllText((Join-Path (Get-InstallerUiDataRoot) 'draft-config.json'),'draft manually edited')
        [IO.File]::WriteAllText((Join-Path (Get-InstallerUiDataRoot) 'unknown.txt'),'unknown ui file')
        foreach ($name in @('config.json','config.json.previous','user-owned.txt','user-backups/upgrade-preserved.json')) {
            $path=Join-Path $fixture.Data $name
            [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path)) | Out-Null
            [IO.File]::WriteAllText($path,'manually modified '+$name)
        }
        Check ((Save-InstallerUserData ([pscustomobject]@{Root=$fixture.Data}) $true) -ceq '')
        Check (-not (Test-Path -LiteralPath (Get-InstallerRetentionRoot)))
        Remove-InstallerChosenData ([pscustomobject]@{Root=$fixture.Data})
        Check (-not (Test-Path -LiteralPath (Join-Path $fixture.Data 'config.json')) -and -not (Test-Path -LiteralPath (Join-Path $fixture.Data 'config.json.previous')))
        Check (Test-Path -LiteralPath $fixture.Data)
        Check ([IO.File]::ReadAllText((Join-Path $fixture.Data 'user-owned.txt')) -ceq 'manually modified user-owned.txt')
        Check (Test-Path -LiteralPath (Join-Path $fixture.Data 'user-backups/upgrade-preserved.json'))
        Check (-not (Test-Path -LiteralPath (Join-Path (Get-InstallerUiDataRoot) 'draft-config.json')))
        Check (Test-Path -LiteralPath (Join-Path (Get-InstallerUiDataRoot) 'unknown.txt'))
    } finally { Remove-Fixture }
}
Case 'Fresh activation after uninstall preserves occupied former data root and uses a new dedicated root' {
    New-Fixture
    try {
        $historical=Join-Path $fixture.Base 'WiFiProxySwitcher'
        Check ((Get-DefaultEngineInstallDirectory $fixture.Base) -ceq $historical)
        [IO.Directory]::CreateDirectory($historical) | Out-Null
        $userFile=Join-Path $historical 'config.json'; [IO.File]::WriteAllText($userFile,'retained user-modified configuration')
        $fresh=Get-DefaultEngineInstallDirectory $fixture.Base
        Check ($fresh -match 'WiFiProxyPilot-Data[\\/]engine-[0-9a-f]{32}$')
        Check (-not (Test-Path -LiteralPath $fresh))
        Check ([IO.File]::ReadAllText($userFile) -ceq 'retained user-modified configuration')
        Check (@(Get-ChildItem -LiteralPath $historical -Force).Count -eq 1)
    } finally { Remove-Fixture }
}
Case 'Actual PowerShell JSON result encoding matches installer success and conflict protocol' {
    New-Fixture
    try {
        $path=Join-Path $fixture.Base 'actual-result.json'
        Write-JsonAtomic $path ([ordered]@{Succeeded=$true;Code='Completed';Message='path has spaces';Data=$null}) -Compress
        $actual=[IO.File]::ReadAllText($path)
        Check ($actual.Contains('"Succeeded":true')) 'Success token must match actual PowerShell 5.1 compact JSON'
        Check (($actual | ConvertFrom-Json).Message -ceq 'path has spaces')
        Write-JsonAtomic $path ([ordered]@{Succeeded=$false;Code='RestoreConflict';Message='';Data=$null}) -Compress
        $actual=[IO.File]::ReadAllText($path)
        Check ($actual.Contains('"Code":"RestoreConflict"')) 'Conflict token must match actual PowerShell 5.1 compact JSON'
        $iss=Get-Content -LiteralPath (Join-Path $repo 'release/WiFiProxyPilot.iss') -Raw
        Check ($iss.Contains("Pos('"+'"Succeeded":true'+"', Json)"))
        Check ($iss.Contains("Pos('"+'"Code":"RestoreConflict"'+"', Json)"))
    } finally { Remove-Fixture }
}
Case 'Product errors preserve diagnostic text and expose stable machine-readable code' {
    $caught=$null
    try { Throw-ProductError 'WatcherTaskMissing' 'Original diagnostic text' } catch { $caught=$_.Exception }
    Check ($null -ne $caught -and $caught.Message -ceq 'Original diagnostic text')
    Check ($caught.Data['WiFiProxyCode'] -ceq 'WatcherTaskMissing')
}
Case 'Installer setup contract checks result, cancellation, native language and single owner' {
    $iss=Get-Content -LiteralPath (Join-Path $repo 'release/WiFiProxyPilot.iss') -Raw
    Check ($iss.Contains('PrivilegesRequired=lowest') -and $iss.Contains('LanguageDetectionMethod=uilanguage'))
    Check ($iss.Contains('SetupArchitecture=x64') -and $iss.Contains('ExecAndCaptureOutputWithNativeSysDir'))
    Check ($iss.Contains('PrepareToInstall') -and $iss.Contains('InitializeUninstall'))
    Check ($iss.Contains('InspectUninstall') -and $iss.Contains('LoadStringFromFile') -and $iss.Contains('RestoreConflict'))
    Check (-not $iss.Contains('filesandordirs') -and -not $iss.Contains('RunOnce'))
    $build=Get-Content -LiteralPath (Join-Path $repo 'release/Build.ps1') -Raw
    Check ($build.Contains('WiFiProxyPilot-Setup-x64.exe') -and $build.Contains('PublishSingleFile=false'))
    Check ($build.Contains('WiFiProxyPilot-Portable-x64.zip'))
}
if ($testOutput) { Write-JsonAtomic $testOutput @($results) }
if (@($results | Where-Object { -not $_.Passed }).Count) { exit 1 }
exit 0

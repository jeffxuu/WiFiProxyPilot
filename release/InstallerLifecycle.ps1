#requires -Version 5.1
[CmdletBinding()]
param(
    [ValidateSet('PrepareInstall','CommitInstall','InspectUninstall','Uninstall')][string]$Action='InspectUninstall',
    [string]$AppDir='',
    [string]$EngineSource='',
    [ValidateSet('Restore','Keep')][string]$ProxyChoice='Restore',
    [switch]$DeleteUserData,
    [string]$ResultPath='',
    [switch]$ImportOnly
)
$ErrorActionPreference='Stop'
if (-not $EngineSource) { $EngineSource=Join-Path $PSScriptRoot 'engine' }
. (Join-Path $EngineSource 'lib/Core.ps1')
. (Join-Path $EngineSource 'lib/Windows.ps1')
. (Join-Path $EngineSource 'lib/Lifecycle.ps1')
. (Join-Path $EngineSource 'lib/Desktop.ps1')

function Assert-InstallerAppPath([string]$Directory) {
    if (-not [IO.Path]::IsPathRooted($Directory) -or $Directory.StartsWith('\\')) { throw 'Install directory must be a local absolute path' }
    $full=[IO.Path]::GetFullPath($Directory).TrimEnd('\')
    if ($full -eq [IO.Path]::GetPathRoot($full).TrimEnd('\') -or $full -match '["\r\n]') { throw 'Install directory must be a dedicated application subdirectory' }
    Assert-PlainPath $full
    $root=Get-InstalledRoot
    if ($root -and ([string]::Equals($root,$full,[StringComparison]::OrdinalIgnoreCase) -or $full.StartsWith($root.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase))) { throw 'Program directory must be separate from preserved engine data' }
    return $full
}
function Get-InstallerEngine {
    $root=Get-InstalledRoot
    if (-not $root) { return $null }
    return Read-Install $root
}
function Get-InstallerTaskState($Manifest) {
    $task=Get-OwnedTask $Manifest
    $enabled=$false; $running=$false
    if ($null -ne $task) {
        $running=([string](Get-TaskField $task 'State')) -in @('Running','Queued')
        $value=Get-TaskField (Get-TaskField $task 'Settings') 'Enabled'
        if ($null -ne $value) { $enabled=[bool]$value } else { $enabled=([string](Get-TaskField $task 'State')) -ne 'Disabled' }
    }
    return [pscustomobject]@{Task=$task;Enabled=$enabled;Running=$running;HadStop=(Test-Path -LiteralPath (Join-Path $Manifest.Root 'state/stop.request'))}
}
function Test-InstallerRestoreConflict($Manifest) {
    if ($null -eq $Manifest -or ($null -ne $Manifest.PSObject.Properties['Phase'] -and $Manifest.Phase -eq 'Uninstalling')) { return $false }
    $original=Read-OriginalProxy $Manifest.Root
    $current=Get-ManualSnapshot
    if (Test-RestoreAllowed $current $original) { return $false }
    $last=$null; $lastPath=Join-Path $Manifest.Root 'state/last-applied.json'; Assert-PlainPath $lastPath
    if (Test-Path -LiteralPath $lastPath) { $last=Get-Content -LiteralPath $lastPath -Raw -Encoding UTF8 | ConvertFrom-Json }
    return -not (Test-RestoreAllowed $current $last)
}
function Stop-InstallerGui([string]$Directory,$Legacy) {
    $exe=Join-Path $Directory 'WiFiProxyPilot.exe'
    $running=@(Get-CimInstance Win32_Process -Filter "Name='WiFiProxyPilot.exe'" | Where-Object { [string]::Equals($_.ExecutablePath,$exe,[StringComparison]::OrdinalIgnoreCase) })
    if ($running.Count -gt 0 -or (Test-Path -LiteralPath (Join-Path $Directory 'installer-owned.json'))) {
        foreach ($candidate in $running) {
            $identity=Invoke-CimMethod -InputObject $candidate -MethodName GetOwnerSid
            if ($identity.ReturnValue -ne 0 -or $identity.Sid -cne (Get-UserSid)) { throw 'GUI process owner does not match the installing user' }
        }
        # The EXE owns the SID/session IPC identity and verifies the active interactive user.
        $process=Start-Process -FilePath $exe -ArgumentList '/shutdown-ui' -WindowStyle Hidden -PassThru
        if (-not $process.WaitForExit(30000) -or $process.ExitCode -ne 0) { throw 'Could not close the running application; close WiFi Proxy Pilot and retry' }
    }
    if ($null -eq $Legacy) { return }
    foreach ($file in $Legacy.Files) {
        $path=Join-Path $Legacy.Root $file.Path; Assert-PlainPath $path
        if (-not (Test-Path -LiteralPath $path)) { continue }
        if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -cne $file.Hash) { throw 'Legacy application file changed; refusing to stop an unrecognized process' }
        foreach ($candidate in @(Get-CimInstance Win32_Process -Filter "Name='WiFiProxySwitcher.exe'")) {
            if (-not [string]::Equals($candidate.ExecutablePath,$path,[StringComparison]::OrdinalIgnoreCase)) { continue }
            $owner=Invoke-CimMethod -InputObject $candidate -MethodName GetOwnerSid
            if ($owner.ReturnValue -ne 0 -or $owner.Sid -cne (Get-UserSid)) { throw 'Legacy GUI process owner does not match the installing user' }
            $gui=[Diagnostics.Process]::GetProcessById([int]$candidate.ProcessId)
            try {
                # v3.2 has no exit IPC; verified legacy desktop GUI may be terminated for migration.
                $gui.Kill(); if (-not $gui.WaitForExit(15000)) { throw 'Legacy GUI did not exit' }
            } finally { $gui.Dispose() }
        }
    }
}
function Assert-InstallerLegacy($Manifest) {
    if ($null -eq $Manifest) { return $null }
    Read-OriginalProxy $Manifest.Root | Out-Null
    Get-OwnedTask $Manifest | Out-Null
    $desktop=Read-DesktopInstall $Manifest.Root
    if ($null -ne $desktop) {
        Assert-DesktopRegistration $Manifest.Root $desktop
        foreach ($file in $desktop.Files) {
            $path=Join-Path $Manifest.Root $file.Path
            if ((Test-Path -LiteralPath $path) -and (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -cne $file.Hash) { throw 'Modified legacy executable must be reviewed before migration' }
        }
    }
    return $desktop
}
function Assert-InstallerPending([string]$Directory) {
    $path=Join-Path $Directory 'installer-pending.json'; Assert-PlainPath $path
    if (-not (Test-Path -LiteralPath $path)) { return $false }
    $pending=Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($pending.Product -cne 'WiFiProxyPilot-Inno-Pending-v1' -or $pending.OwnerSid -cne (Get-UserSid) -or $pending.AppId -cne '{15F7908C-5C54-4D45-9343-1973BFEA3B47}' -or -not [string]::Equals($pending.AppDir,$Directory,[StringComparison]::OrdinalIgnoreCase)) { throw 'Interrupted setup receipt belongs to another user/directory' }
    $allowed=@{}
    foreach ($file in $pending.Files) {
        if ($file.Path -match '(^|/)\.\.?(/|$)' -or $file.Path -match '[:\\\r\n]' -or $file.Path.StartsWith('/') -or $file.Hash -cnotmatch '^[A-F0-9]{64}$' -or $allowed.ContainsKey($file.Path)) { throw 'Interrupted setup file receipt is invalid' }
        $allowed[$file.Path]=$file.Hash
    }
    if ($allowed.Count -lt 1) { throw 'Interrupted setup receipt has no owned files' }
    foreach ($entry in Get-ChildItem -LiteralPath $Directory -Recurse -Force) {
        Assert-PlainPath $entry.FullName
        if ($entry.PSIsContainer) { continue }
        $relative=$entry.FullName.Substring($Directory.Length+1).Replace('\','/')
        if ($relative -in @('installer-pending.json','installer-files.json') -or $relative -cmatch '^unins[0-9]{3}\.(exe|dat)$') { continue }
        if (-not $allowed.ContainsKey($relative) -or (Get-FileHash -LiteralPath $entry.FullName -Algorithm SHA256).Hash -cne $allowed[$relative]) { throw ('Interrupted setup contains an unowned or modified file; preserving it: '+$relative) }
    }
    return $true
}
function Write-InstallerPending([string]$Directory) {
    $filesPath=Join-Path $PSScriptRoot 'installer-files.json'; Assert-PlainPath $filesPath
    $receipt=Get-Content -LiteralPath $filesPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $pending=[pscustomobject]@{Product='WiFiProxyPilot-Inno-Pending-v1';OwnerSid=(Get-UserSid);AppDir=$Directory;AppId='{15F7908C-5C54-4D45-9343-1973BFEA3B47}';Version=$receipt.Version;Files=$receipt.Files}
    [IO.Directory]::CreateDirectory($Directory) | Out-Null
    Protect-InstallDirectory $Directory
    Write-JsonAtomic (Join-Path $Directory 'installer-pending.json') $pending
}
function Invoke-InstallerPrepare([string]$Directory) {
    $directory=Assert-InstallerAppPath $Directory
    $existing=Read-InstallerDesktop
    if ($null -ne $existing -and -not [string]::Equals($existing.AppDir,$directory,[StringComparison]::OrdinalIgnoreCase)) { throw 'An existing per-user installation has another program directory; upgrade at its existing location' }
    if ((Test-Path -LiteralPath $directory) -and $null -eq $existing -and @(Get-ChildItem -LiteralPath $directory -Force).Count -and -not (Assert-InstallerPending $directory)) { throw 'Target directory contains unowned files; choose an empty application directory' }
    if ($null -ne $existing) {
        $owned=Assert-InstallerApplicationFiles $existing
        $incoming=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'installer-files.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($file in $incoming.Files) {
            $path=Join-Path $directory $file.Path; Assert-PlainPath $path
            if ((Test-Path -LiteralPath $path) -and -not $owned.ContainsKey($file.Path)) { Throw-ProductError 'InstallerAppModified' ('A new program path is occupied by an unowned file; preserving it: '+$file.Path) }
        }
    }
    $manifest=Get-InstallerEngine; $legacy=Assert-InstallerLegacy $manifest
    foreach ($name in Get-DistributionFiles) { if (-not (Test-Path -LiteralPath (Join-Path $EngineSource $name) -PathType Leaf)) { throw ('Installer engine payload is incomplete: '+$name) } }
    Stop-InstallerGui $directory $legacy
    Write-InstallerPending $directory
    return @{AppDir=$directory;EngineRoot=$(if ($null -ne $manifest) { $manifest.Root } else { '' });ProxyModified=$false}
}
function Invoke-InstallerCommit([string]$Directory) {
    $directory=Assert-InstallerAppPath $Directory
    $manifest=Get-InstallerEngine; $legacy=Assert-InstallerLegacy $manifest
    # Install-ProductUpgrade stages and hashes first, then preserves original config/backup and
    # rolls back engine files and task state on failure. It never creates another watcher task.
    if ($null -ne $manifest) {
        $taskState=Get-InstallerTaskState $manifest
        $updated=Install-ProductFiles $EngineSource $manifest.Root $manifest
        if ($taskState.Running -and -not $taskState.HadStop) {
            Start-OwnedWatcher $updated
            if (-not $taskState.Enabled) { Disable-ScheduledTask -TaskName $updated.TaskName -TaskPath '\' -ErrorAction Stop | Out-Null }
        } else { Restore-UpgradeTaskState $updated $taskState.Task $taskState.Enabled $false $taskState.HadStop }
        # Retain a migration receipt before retiring owned legacy desktop entries.
        if ($null -ne $legacy) {
            Write-JsonAtomic (Join-Path $manifest.Root 'user-backups/desktop-migration-v33.json') $legacy
            Remove-DesktopFiles $legacy
        }
    }
    $owner=[pscustomobject]@{Product='WiFiProxyPilot-Inno-v1';OwnerSid=(Get-UserSid);AppDir=$directory;Version='3.3.0-beta.1';AppId='{15F7908C-5C54-4D45-9343-1973BFEA3B47}';ReceiptSha256=(Get-FileHash -LiteralPath (Join-Path $directory 'installer-files.json') -Algorithm SHA256).Hash;UninstallerSha256=(Get-FileHash -LiteralPath (Join-Path $directory 'unins000.exe') -Algorithm SHA256).Hash}
    Write-JsonAtomic (Join-Path $directory 'installer-owned.json') $owner
    $key=[Microsoft.Win32.Registry]::CurrentUser.CreateSubKey('Software\WiFiProxySwitcher')
    try { $key.SetValue('DesktopOwner','Inno'); $key.SetValue('DesktopAppDir',$directory) } finally { $key.Dispose() }
    if ($null -ne $manifest) {
        $config=Read-Configuration (Join-Path $manifest.Root 'config.json')
        $tray=$true; if ($null -ne $config.PSObject.Properties['TrayAutoStart']) { $tray=$config.TrayAutoStart }
        Set-InstallerTrayLogin $owner $tray
    }
    $pending=Join-Path $directory 'installer-pending.json'; Assert-PlainPath $pending
    if (Test-Path -LiteralPath $pending) { Remove-Item -LiteralPath $pending -Force }
    return @{AppDir=$directory;EngineRoot=$(if ($null -ne $manifest) { $manifest.Root } else { '' });ProxyModified=$false;InstallationOwner='Inno'}
}
function Get-InstallerRetentionRoot { return Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'WiFiProxyPilot-Retained' }
function Get-InstallerUiDataRoot { return Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'WiFiProxySwitcher-Control' }
function Get-InstallerUiDataNames { return @('preferences.json','draft-config.json','control-errors.log','control-errors.log.1','commands.jsonl','commands.jsonl.1','desktop-errors.log','desktop-errors.log.1') }
function Save-InstallerUserData($Manifest,[bool]$Delete) {
    # Copy durable user data to a separate, named retention directory before engine cleanup.
    # Never recursively delete an application data root, including when delete was selected.
    $retained=Get-InstallerRetentionRoot
    $target=Join-Path $retained ('uninstall-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+[Guid]::NewGuid().ToString('N'))
    Assert-PlainPath $target
    $files=@()
    if ($null -ne $Manifest) { $files=@('config.json','config.json.previous','state/proxy-before-install.json') }
    if ($null -ne $Manifest -and (Test-Path -LiteralPath (Join-Path $Manifest.Root 'logs'))) {
        $files+=@(Get-ChildItem -LiteralPath (Join-Path $Manifest.Root 'logs') -File | Where-Object { $_.Name -match '^watcher\.jsonl(\.[0-9]+)?$' } | ForEach-Object { 'logs/'+$_.Name })
    }
    if (-not $Delete) {
        foreach ($name in $files) {
            $source=Join-Path $Manifest.Root $name; Assert-PlainPath $source
            if (Test-Path -LiteralPath $source) { Copy-UpgradeFileAtomic $source (Join-Path $target $name) }
        }
        $uiRoot=Get-InstallerUiDataRoot
        foreach ($name in Get-InstallerUiDataNames) {
            $source=Join-Path $uiRoot $name; Assert-PlainPath $source
            if (Test-Path -LiteralPath $source) { Copy-UpgradeFileAtomic $source (Join-Path $target ('ui/'+$name)) }
        }
        return $target
    }
    return ''
}
function Remove-InstallerChosenData($Manifest) {
    if ($null -ne $Manifest) {
        foreach ($name in @('config.json','config.json.previous')) {
            $path=Join-Path $Manifest.Root $name; Assert-PlainPath $path
            if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
        }
    }
    foreach ($name in Get-InstallerUiDataNames) {
        $path=Join-Path (Get-InstallerUiDataRoot) $name; Assert-PlainPath $path
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
    }
}
function Invoke-InstallerUninstall([string]$Directory,[string]$Choice,[bool]$Delete) {
    $owner=Assert-InstallerDesktopDirectory $Directory
    $manifest=Get-InstallerEngine
    $legacy=$null; if ($null -ne $manifest) { $legacy=Assert-InstallerLegacy $manifest }
    # All choices and restore checks happen before the GUI, watcher, intent or task changes.
    if ($Choice -notin @('Restore','Keep')) { throw 'Uninstall canceled; no changes were made' }
    $retained=Save-InstallerUserData $manifest $Delete
    Stop-InstallerGui $owner.AppDir $legacy
    Set-InstallerTrayLogin $owner $false
    if ($null -ne $manifest) {
        Uninstall-Product $manifest -KeepCurrentProxy:($Choice -eq 'Keep') -ForceRestore:($Choice -eq 'Restore') -DeleteLogs:$Delete
        if ($null -ne $legacy) { Remove-DesktopFiles $legacy }
        if ($null -ne (Get-OwnedTask $manifest) -or (Get-InstalledRoot)) { throw 'Engine uninstall verification failed: task or pointer remains' }
    }
    if ($Delete) { Remove-InstallerChosenData $manifest }
    $key=[Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Software\WiFiProxySwitcher',$true)
    if ($null -ne $key) {
        try {
            if ($key.GetValue('DesktopOwner','') -cne 'Inno' -or -not [string]::Equals([string]$key.GetValue('DesktopAppDir',''),$owner.AppDir,[StringComparison]::OrdinalIgnoreCase)) { throw 'Installer pointer ownership changed; uninstall paused' }
            $key.DeleteValue('DesktopOwner',$false); $key.DeleteValue('DesktopAppDir',$false)
        } finally { $key.Dispose() }
    }
    return @{EngineRemoved=$true;RetainedData=$retained;ProxyChoice=$Choice;DeleteUserData=$Delete;ProgramFilesOwner='Inno'}
}
if ($ImportOnly) { return }
$result=[ordered]@{Succeeded=$false;Code='InstallerFailed';Message='';Data=$null}; $exitCode=1; $gate=$null; $taken=$false
try {
    Initialize-Windows
    if (-not [Environment]::Is64BitProcess) { throw 'Installer lifecycle requires 64-bit Windows PowerShell' }
    $gate=New-UserMutex 'Control'; $taken=Enter-Mutex $gate 30000
    if (-not $taken) { throw 'Another lifecycle operation is in progress' }
    switch ($Action) {
        'PrepareInstall' { $result.Data=Invoke-InstallerPrepare $AppDir }
        'CommitInstall' { $result.Data=Invoke-InstallerCommit $AppDir }
        'InspectUninstall' {
            Assert-InstallerDesktopDirectory $AppDir | Out-Null
            $manifest=Get-InstallerEngine; Assert-InstallerLegacy $manifest | Out-Null
            $conflict=Test-InstallerRestoreConflict $manifest
            $result.Data=@{RestoreConflict=$conflict;EngineInstalled=($null -ne $manifest)}
            if ($conflict) { $result.Code='RestoreConflict'; $exitCode=20 }
        }
        'Uninstall' { $result.Data=Invoke-InstallerUninstall $AppDir $ProxyChoice ([bool]$DeleteUserData) }
    }
    if ($exitCode -ne 20) { $exitCode=0; $result.Code='Completed'; $result.Succeeded=$true }
} catch {
    $result.Message=$_.Exception.Message
    if ($_.Exception.Data.Contains('WiFiProxyCode')) { $result.Code=[string]$_.Exception.Data['WiFiProxyCode'] }
    Write-ControlFailure ('Installer/'+$Action) $_.Exception.Message
}
finally { if ($taken) { $gate.ReleaseMutex() }; if ($null -ne $gate) { $gate.Dispose() } }
if ($ResultPath) {
    try { Write-JsonAtomic $ResultPath $result -Compress }
    catch { Write-ControlFailure 'Installer/Result' $_.Exception.Message; $exitCode=1 }
}
exit $exitCode

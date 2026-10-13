#requires -Version 5.1
[CmdletBinding()]
param([string]$ResultPath='', [string]$NameFilter='')
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
. (Join-Path $repo 'lib/Core.ps1')
. (Join-Path $repo 'lib/Windows.ps1')
. (Join-Path $repo 'lib/Lifecycle.ps1')
$copyImplementation=${function:Copy-UpgradeFileAtomic}
$writeImplementation=${function:Write-JsonAtomic}
$enterImplementation=${function:Enter-Mutex}
$results=[Collections.Generic.List[object]]::new()
function Assert([bool]$Condition,[string]$Message) { if (-not $Condition) { throw $Message } }
function Get-UserSid { 'S-1-5-21-100-200-300-1001' }
function Assert-ProxyPolicy {}
function Protect-InstallDirectory([string]$Root) {}
function Get-ManualSnapshot {
    return [pscustomobject]@{ProxyEnable=[pscustomobject]@{Exists=$true;Kind='DWord';Value=0};ProxyServer=[pscustomobject]@{Exists=$true;Kind='String';Value='original.example.test:80'};ProxyOverride=[pscustomobject]@{Exists=$true;Kind='String';Value='original.example.test'}}
}
function Get-OwnedTask($Manifest) { return $script:fixture.Task }
function Stop-OwnedWatcher($Manifest) {
    $script:fixture.Stops++; $script:fixture.Task.State='Ready'; $script:fixture.Task.Settings.Enabled=$false
    [IO.File]::WriteAllText((Join-Path $Manifest.Root 'state/stop.request'),'stop')
}
function Enable-ScheduledTask { param($TaskName,$TaskPath,$ErrorAction) $script:fixture.Task.Settings.Enabled=$true }
function Disable-ScheduledTask { param($TaskName,$TaskPath,$ErrorAction) $script:fixture.Task.Settings.Enabled=$false }
function Start-ScheduledTask { param($TaskName,$TaskPath,$ErrorAction) $script:fixture.Starts++; $script:fixture.Task.State='Running'; $script:fixture.StartedIntent=(Read-Configuration (Join-Path $script:fixture.Root 'config.json')).ManagementIntent }
function Copy-UpgradeFileAtomic([string]$Source,[string]$Destination) {
    $f=$script:fixture
    if ($f.Fault -eq 'stage' -and $Destination.Contains('.upgrade.') -and $Destination.EndsWith('Monitor.ps1') -and -not $f.Faulted) { $f.Faulted=$true; throw 'injected stage copy failure' }
    if ($f.Fault -eq 'rollback' -and $Source.Contains('user-backups') -and $Destination -eq (Join-Path $f.Root 'Control.ps1')) { $f.RollbackFaulted=$true; throw 'injected rollback failure' }
    & $copyImplementation $Source $Destination
    if ($f.Fault -in @('commit','rollback') -and $Destination -eq (Join-Path $f.Root 'lib/Monitor.ps1') -and -not $f.Faulted) { $f.Faulted=$true; throw 'injected failure after atomic payload replacement' }
}
function Write-JsonAtomic([string]$Path,$Value,[string]$BackupPath='') {
    $f=$script:fixture
    if ($f.Fault -eq 'config' -and $Path -eq (Join-Path $f.Root 'config.json') -and -not $f.Faulted) { $f.Faulted=$true; throw 'injected configuration save failure' }
    if ($f.Fault -eq 'manifest' -and $Path -eq (Join-Path $f.Root 'state/installation.json') -and $f.Task -ne $null -and -not $f.Faulted) { $f.Faulted=$true; throw 'injected installation manifest save failure' }
    & $writeImplementation $Path $Value $BackupPath
}
function Enter-Mutex($Mutex,[int]$Milliseconds=0) {
    if ($script:fixture.Fault -eq 'gate' -and $Milliseconds -eq 5000) { $script:fixture.Faulted=$true; return $false }
    return & $enterImplementation $Mutex $Milliseconds
}
function Hash([string]$Path) { if (Test-Path -LiteralPath $Path) { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }; return '<absent>' }
function New-Fixture([string]$Fault,[string]$Intent='Paused') {
    $base=Join-Path ([IO.Path]::GetTempPath()) ('WiFiUpgradeTransaction-'+[Guid]::NewGuid().ToString('N'))
    $script:fixture=@{Base=$base;Source=(Join-Path $base 'source');Root=(Join-Path $base 'installed');Task=$null;Stops=0;Starts=0;StartedIntent='';Fault='';Faulted=$false;RollbackFaulted=$false;Before=@{};Intent=$Intent}
    foreach ($name in Get-DistributionFiles) {
        $path=Join-Path $script:fixture.Source $name
        [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path)) | Out-Null
        [IO.File]::WriteAllText($path,('original fixture payload '+$name))
    }
    $config=Get-Content -LiteralPath (Join-Path $repo 'config.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $config.ManagementIntent=$Intent; $config.SetupComplete=$true; $config.Whitelist=@('Demo Office',' Home ')
    Write-JsonAtomic (Join-Path $script:fixture.Source 'config.json') $config
    $script:fixture.Manifest=Install-ProductFiles $script:fixture.Source $script:fixture.Root $null
    Remove-Item -LiteralPath (Join-Path $script:fixture.Root 'state/stop.request') -Force
    # Exercise migration of the real installed v1 pause marker, not the source default.
    if ($Intent -eq 'Paused') {
        $config.PSObject.Properties.Remove('SchemaVersion'); $config.PSObject.Properties.Remove('ManagementIntent'); $config.PSObject.Properties.Remove('SetupComplete')
        Write-JsonAtomic (Join-Path $script:fixture.Root 'config.json') $config
        [IO.File]::WriteAllText((Join-Path $script:fixture.Root 'state/pause.request'),'legacy pause')
    }
    Write-JsonAtomic (Join-Path $script:fixture.Root 'config.json.previous') @{Earlier='preserve exact previous bytes'}
    foreach ($name in @(@(Get-DistributionFiles)+@('config.json.previous','state/installation.json','state/proxy-before-install.json','state/last-applied.json','state/pause.request','state/stop.request'))) {
        $script:fixture.Before[$name]=Hash (Join-Path $script:fixture.Root $name)
    }
    [IO.File]::WriteAllText((Join-Path $script:fixture.Source 'Control.ps1'),'new control payload')
    [IO.File]::WriteAllText((Join-Path $script:fixture.Source 'lib/Monitor.ps1'),'new monitor payload')
    $script:fixture.Task=[pscustomobject]@{State='Running';Settings=[pscustomobject]@{Enabled=$true}}
    $script:fixture.Fault=$Fault
}
function Assert-RolledBack {
    foreach ($name in $script:fixture.Before.Keys) { Assert ((Hash (Join-Path $script:fixture.Root $name)) -ceq $script:fixture.Before[$name]) ('original bytes changed: '+$name) }
    Assert (-not (Test-Path -LiteralPath (Join-Path $script:fixture.Root 'state/upgrade-recovery.json'))) 'completed rollback left a recovery block'
    Assert ($script:fixture.Task.Settings.Enabled -and $script:fixture.Task.State -eq 'Running') 'original task state not restored'
    Assert ((Read-Configuration (Join-Path $script:fixture.Root 'config.json')).ManagementIntent -eq $script:fixture.Intent) 'saved intent was overridden'
}
function Case([string]$Name,[scriptblock]$Body) {
    if ($NameFilter -and $Name -notmatch $NameFilter) { return }
    try { & $Body; $results.Add([pscustomobject]@{Name=$Name;Passed=$true;Error=''}); Write-Host ('PASS '+$Name) }
    catch { $results.Add([pscustomobject]@{Name=$Name;Passed=$false;Error=$_.Exception.Message;Stack=$_.ScriptStackTrace}); Write-Host ('FAIL '+$Name+': '+$_.Exception.Message) }
    finally {
        if ($null -ne $script:fixture) {
            $full=[IO.Path]::GetFullPath($script:fixture.Base); $parent=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
            if (-not $full.StartsWith($parent,[StringComparison]::OrdinalIgnoreCase) -or $full -notmatch 'WiFiUpgradeTransaction-[0-9a-f]{32}$') { throw 'refusing unsafe fixture cleanup' }
            if (Test-Path -LiteralPath $full) { Remove-Item -LiteralPath $full -Recurse -Force }
        }
    }
}
Case 'Upgrade stage failure leaves watcher/files untouched' {
    New-Fixture 'stage'; $failed=$false
    try { Install-ProductFiles $script:fixture.Source $script:fixture.Root $script:fixture.Manifest | Out-Null } catch { $failed=$true }
    Assert ($failed -and $script:fixture.Faulted) 'expected injected stage failure was not reached'; Assert ($script:fixture.Stops -eq 0) 'watcher stopped before verified staging'; Assert-RolledBack
}
Case 'Configuration gate contention leaves watcher/files untouched' {
    New-Fixture 'gate'; $failed=$false
    try { Install-ProductFiles $script:fixture.Source $script:fixture.Root $script:fixture.Manifest | Out-Null } catch { $failed=$true }
    Assert ($failed -and $script:fixture.Faulted) 'expected injected gate failure was not reached'; Assert ($script:fixture.Stops -eq 0) 'watcher stopped before taking gate'; Assert-RolledBack
}
Case 'Partial payload replacement rolls back bytes/task and legacy pause' {
    New-Fixture 'commit'; $failed=$false
    try { Install-ProductFiles $script:fixture.Source $script:fixture.Root $script:fixture.Manifest | Out-Null } catch { $failed=$true }
    Assert ($failed -and $script:fixture.Faulted) 'expected injected commit failure was not reached'; Assert-RolledBack; Assert ($script:fixture.Starts -eq 1 -and $script:fixture.StartedIntent -eq 'Paused') 'rollback restart changed pause intent'
}
Case 'Configuration failure restores complete payload and prior config' {
    New-Fixture 'config'; $failed=$false
    try { Install-ProductFiles $script:fixture.Source $script:fixture.Root $script:fixture.Manifest | Out-Null } catch { $failed=$true }
    Assert ($failed -and $script:fixture.Faulted) 'expected injected config failure was not reached'; Assert-RolledBack
}
Case 'Manifest failure preserves Direct intent and original backup' {
    New-Fixture 'manifest' 'Direct'; $failed=$false
    try { Install-ProductFiles $script:fixture.Source $script:fixture.Root $script:fixture.Manifest | Out-Null } catch { $failed=$true }
    Assert ($failed -and $script:fixture.Faulted) 'expected injected manifest failure was not reached'; Assert-RolledBack; Assert ($script:fixture.StartedIntent -eq 'Direct') 'rollback restart changed Direct intent'
}
Case 'Successful migration keeps rules/config ownership and full rollback backup' {
    New-Fixture ''; $updated=Install-ProductFiles $script:fixture.Source $script:fixture.Root $script:fixture.Manifest
    $saved=Read-Configuration (Join-Path $script:fixture.Root 'config.json')
    Assert ($saved.SchemaVersion -eq 2 -and $saved.ManagementIntent -eq 'Paused' -and $saved.Whitelist.Count -eq 2 -and $saved.Whitelist[1] -ceq ' Home ') 'migration reset installed rules/intent'
    $old=@($script:fixture.Manifest.Files | Where-Object {$_.Path -eq 'config.json'})[0].Hash
    Assert (@($updated.Files | Where-Object {$_.Path -eq 'config.json'})[0].Hash -ceq $old) 'migration reclaimed user config ownership'
    Assert ((Hash (Join-Path $script:fixture.Root 'state/proxy-before-install.json')) -ceq $script:fixture.Before['state/proxy-before-install.json']) 'original proxy backup changed'
    Assert (-not (Test-Path -LiteralPath (Join-Path $script:fixture.Root 'state/upgrade-recovery.json'))) 'successful upgrade left a recovery block'
    $backups=@(Get-ChildItem -LiteralPath (Join-Path $script:fixture.Root 'user-backups') -Directory)
    Assert ($backups.Count -eq 1 -and (Test-Path -LiteralPath (Join-Path $backups[0].FullName 'state/installation.json')) -and (Test-Path -LiteralPath (Join-Path $backups[0].FullName 'config.json.previous'))) 'rollback backup/manifest not retained'
}
Case 'Incomplete rollback retains recovery/stop protection and blocks startup' {
    New-Fixture 'rollback'; $failed=$false
    try { Install-ProductFiles $script:fixture.Source $script:fixture.Root $script:fixture.Manifest | Out-Null } catch { $failed=$true }
    Assert ($failed -and $script:fixture.Faulted -and $script:fixture.RollbackFaulted) 'expected injected rollback failure was not reached'
    Assert ((Test-Path -LiteralPath (Join-Path $script:fixture.Root 'state/upgrade-recovery.json')) -and (Test-Path -LiteralPath (Join-Path $script:fixture.Root 'state/stop.request'))) 'incomplete rollback lost recovery protection'
    Assert ($script:fixture.Starts -eq 0 -and -not $script:fixture.Task.Settings.Enabled) 'mixed payload was restarted'
    $blocked=$false; try { Start-OwnedWatcher $script:fixture.Manifest } catch { $blocked=$_.Exception.Message.Contains('升级恢复尚未完成') }; Assert $blocked 'startup ignored recovery block'
}
Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Threading;
public sealed class UpgradeTestFileLock : IDisposable {
    private readonly FileStream stream;
    private readonly Thread releaser;
    public UpgradeTestFileLock(string path, int milliseconds) {
        stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
        if (milliseconds > 0) {
            releaser = new Thread(() => { Thread.Sleep(milliseconds); stream.Dispose(); });
            releaser.IsBackground = true; releaser.Start();
        }
    }
    public void Dispose() { if (releaser != null) releaser.Join(); stream.Dispose(); }
}
'@
function New-CopyFixture {
    $base=Join-Path ([IO.Path]::GetTempPath()) ('WiFiUpgradeTransaction-'+[Guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($base) | Out-Null
    $script:fixture=@{Base=$base}
    return $base
}
Case 'Long payload backup paths use a short atomic temporary filename' {
    $base=New-CopyFixture; $source=Join-Path $base 'source.txt'
    $directory=Join-Path $base ('p'*(190-$base.Length-1)); [IO.Directory]::CreateDirectory($directory) | Out-Null
    $destination=Join-Path $directory 'WINDOWS-DESKTOP-RUNTIME-LICENSE.txt'
    Assert (($destination+'.upgrade-tmp.'+('a'*32)).Length -ge 260) 'fixture does not reproduce the former path limit'
    [IO.File]::WriteAllText($source,'new complete payload'); [IO.File]::WriteAllText($destination,'previous payload')
    & $copyImplementation $source $destination
    Assert (([IO.File]::ReadAllText($destination)) -ceq 'new complete payload') 'long-path replacement failed'
    Assert (@(Get-ChildItem -LiteralPath $directory -Force).Count -eq 1) 'atomic temporary file was not cleaned'
}
Case 'Transient Windows sharing lock permits verified atomic replacement after release' {
    $base=New-CopyFixture; $source=Join-Path $base 'source.txt'; $destination=Join-Path $base 'destination.txt'
    [IO.File]::WriteAllText($source,'new complete payload'); [IO.File]::WriteAllText($destination,'previous payload')
    $held=[UpgradeTestFileLock]::new($destination,600); $clock=[Diagnostics.Stopwatch]::StartNew()
    try { & $copyImplementation $source $destination } finally { $held.Dispose() }
    Assert (([IO.File]::ReadAllText($destination)) -ceq 'new complete payload') 'released lock did not allow replacement'
    Assert ($clock.ElapsedMilliseconds -ge 350 -and $clock.ElapsedMilliseconds -lt 8000) 'replacement did not wait within the bounded lock window'
    Assert (@(Get-ChildItem -LiteralPath $base -Force).Count -eq 2) 'atomic temporary file was not cleaned'
}
Case 'Persistent Windows sharing lock fails with paths and preserves the valid destination' {
    $base=New-CopyFixture; $source=Join-Path $base 'source.txt'; $destination=Join-Path $base 'destination.txt'
    [IO.File]::WriteAllText($source,'new complete payload'); [IO.File]::WriteAllText($destination,'previous payload')
    $before=Hash $destination; $held=[UpgradeTestFileLock]::new($destination,0); $clock=[Diagnostics.Stopwatch]::StartNew(); $errorText=''
    try { & $copyImplementation $source $destination } catch { $errorText=$_.Exception.Message } finally { $held.Dispose() }
    Assert ($errorText.Contains($source) -and $errorText.Contains($destination) -and $errorText.Contains('HResult=0x80070020')) 'persistent lock diagnostics are missing'
    Assert ($clock.ElapsedMilliseconds -lt 8000) 'persistent lock did not fail within the retry limit'
    Assert ((Hash $destination) -ceq $before) 'failed replacement altered the valid destination'
    Assert (@(Get-ChildItem -LiteralPath $base -Force).Count -eq 2) 'failed replacement leaked a temporary file'
}
$failed=@($results | Where-Object {-not $_.Passed}).Count
$report=[ordered]@{Total=$results.Count;Passed=($results.Count-$failed);Failed=$failed;ProxyWritten=$false;TaskWritten=$false;Environment='Isolated fixture, mocked proxy/task/identity operations';Results=$results.ToArray()}
if ($ResultPath) { [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($ResultPath))) | Out-Null; & $writeImplementation $ResultPath $report }
if ($failed) { exit 1 }; exit 0

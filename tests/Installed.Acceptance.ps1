#requires -Version 5.1
[CmdletBinding()]
param([string]$Setup='', [string]$Dotnet='dotnet', [string]$OutputDirectory='release/generated/installed-acceptance')
$ErrorActionPreference='Stop'
# This test intentionally mutates WinINet and installs owned tasks. Never run on an everyday workstation.
if ($env:GITHUB_ACTIONS -ne 'true' -or $env:RUNNER_ENVIRONMENT -ne 'github-hosted') { throw 'Real lifecycle tests require a disposable GitHub-hosted Windows runner.' }
$repo=Split-Path $PSScriptRoot -Parent
if (-not $Setup) { $Setup=Join-Path $repo 'release/dist/WiFiProxyPilot-Setup-x64.exe' }
$Setup=[IO.Path]::GetFullPath($Setup); $OutputDirectory=[IO.Path]::GetFullPath($OutputDirectory)
[IO.Directory]::CreateDirectory($OutputDirectory) | Out-Null
. (Join-Path $repo 'lib/Core.ps1'); . (Join-Path $repo 'lib/Windows.ps1'); . (Join-Path $repo 'lib/Lifecycle.ps1'); . (Join-Path $repo 'lib/Desktop.ps1')
. (Join-Path $repo 'lib/Monitor.ps1')
Initialize-Windows
$original=Get-ManualSnapshot; $automaticBefore=Read-SystemProxy
Write-JsonAtomic (Join-Path $OutputDirectory 'original-proxy.json') $original
$appDir=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Programs/Pilot 验收 Space'
$results=[Collections.Generic.List[object]]::new(); $failed=0
function Assert([bool]$Condition,[string]$Message) { if (-not $Condition) { throw $Message } }
function Test([string]$Name,[scriptblock]$Body) {
    $clock=[Diagnostics.Stopwatch]::StartNew()
    try { & $Body; $results.Add([pscustomobject]@{Name=$Name;Passed=$true;Milliseconds=$clock.ElapsedMilliseconds}); Write-Host ('PASS '+$Name) }
    catch { $script:failed++; $results.Add([pscustomobject]@{Name=$Name;Passed=$false;Error=$_.Exception.Message;Stack=$_.ScriptStackTrace}); Write-Host ('FAIL '+$Name+': '+$_.Exception.Message) }
}
function Run([string]$Exe,[string[]]$Arguments,[int[]]$Codes=@(0)) {
    $p=Start-Process -FilePath $Exe -ArgumentList $Arguments -PassThru -WindowStyle Hidden
    try { if (-not $p.WaitForExit(180000)) { throw 'Process timed out' }; Assert ($p.ExitCode -in $Codes) ('Unexpected exit '+$p.ExitCode+' from '+$Exe); return $p.ExitCode }
    finally { $p.Dispose() }
}
function Install([string]$Language='en-US') {
    Run $Setup @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',('/LANG='+$Language.Replace('-','_')),('/DIR="'+$appDir+'"'),'/TASKS=desktopicon',('/LOG="'+(Join-Path $OutputDirectory ('setup-'+$Language+'.log'))+'"')) | Out-Null
}
function WizardInstall([string]$Language) {
    & $Dotnet run --project (Join-Path $repo 'tests/Desktop.Automation/Desktop.Automation.csproj') --configuration Release -- $Setup (Join-Path $OutputDirectory ('wizard-'+$Language)) --installer-wizard --language $Language --app-dir $appDir
    Assert ($LASTEXITCODE -eq 0) ('Actual '+$Language+' Setup wizard interaction failed')
}
function Remove([string]$Proxy='restore',[string]$Delete='no') {
    Run (Join-Path $appDir 'unins000.exe') @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',('/PROXY='+$Proxy),('/DELETEUSERDATA='+$Delete),('/LOG="'+(Join-Path $OutputDirectory ('uninstall-'+$Proxy+'.log'))+'"')) | Out-Null
}
$arp='HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\{15F7908C-5C54-4D45-9343-1973BFEA3B47}_is1'
try {
    Assert (-not (Get-InstalledRoot)) 'Disposable test account unexpectedly has an existing installation; refusing destructive tests.'
    Test 'Setup failure on an unowned nonempty path permits a safe retry' {
        $blocked=Join-Path $OutputDirectory 'unowned target'; [IO.Directory]::CreateDirectory($blocked) | Out-Null
        $foreign=Join-Path $blocked 'unrelated-user-file.txt'; [IO.File]::WriteAllText($foreign,'preserve this file')
        Run $Setup @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',('/DIR="'+$blocked+'"'),('/LOG="'+(Join-Path $OutputDirectory 'setup-rejected.log')+'"')) @(1,2,5,7,8) | Out-Null
        Assert ([IO.File]::ReadAllText($foreign) -eq 'preserve this file') 'Failed Setup altered an unowned file'
        Assert (-not (Test-Path -LiteralPath $arp)) 'Failed preflight registered a competing installed application'
        Assert (-not (Get-InstalledRoot)) 'Failed preflight activated the watcher'
    }
    Test 'Final Setup EXE fresh install with Chinese/space path and no proxy activation' {
        WizardInstall 'en-US'
        Assert (Test-Path -LiteralPath (Join-Path $appDir 'WiFiProxyPilot.exe')) 'Installed executable missing'
        Assert (-not (Get-InstalledRoot)) 'Software installation must not activate the background engine'
        Assert (Test-RestoreAllowed (Get-ManualSnapshot) $original) 'Setup changed the original proxy'
    }
    Test 'One Windows installed-app entry and native shortcuts with unified icon' {
        $entry=Get-ItemProperty -LiteralPath $arp; Assert ($entry.DisplayName -eq 'WiFi Proxy Pilot') 'Wrong ARP name'; Assert ($entry.DisplayVersion -eq '3.3.0-beta.1') 'Wrong ARP version'
        Assert (-not (Test-Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\WiFiProxySwitcher')) 'Competing legacy uninstall entry'
        foreach ($path in @((Join-Path ([Environment]::GetFolderPath('Programs')) 'WiFi Proxy Pilot.lnk'),(Join-Path ([Environment]::GetFolderPath('Desktop')) 'WiFi Proxy Pilot.lnk'))) {
            Assert (Test-Path -LiteralPath $path) ('Shortcut missing: '+$path)
            $shell=New-Object -ComObject WScript.Shell; $link=$shell.CreateShortcut($path)
            Assert ($link.TargetPath -eq (Join-Path $appDir 'WiFiProxyPilot.exe')) 'Incorrect shortcut target'
            Assert ($link.IconLocation -like '*WiFiProxyPilot.exe*') 'Incorrect shortcut icon'
        }
        $entry | Select-Object DisplayName,DisplayVersion,Publisher,InstallLocation,DisplayIcon,UninstallString | ConvertTo-Json | Set-Content (Join-Path $OutputDirectory 'installed-app.json')
    }
    Test 'Repeated Chinese Setup wizard retains one app registration' { WizardInstall 'zh-CN'; Assert (Test-Path -LiteralPath $arp) 'ARP entry lost' }
    Test 'Actual unconfigured automatic click opens setup without activating proxy' {
        & $Dotnet run --project (Join-Path $repo 'tests/Desktop.Automation/Desktop.Automation.csproj') --configuration Release -- (Join-Path $appDir 'WiFiProxyPilot.exe') (Join-Path $OutputDirectory 'setup-uia') --setup-only
        Assert ($LASTEXITCODE -eq 0) 'Unconfigured actual UIA failed'
        Assert (-not (Get-InstalledRoot)) 'Setup navigation activated the backend without confirmation'
        Assert (Test-RestoreAllowed (Get-ManualSnapshot) $original) 'Setup navigation changed proxy'
    }
    Test 'Installed WPF actual UIA: pages, edit/save/cancel, language, demo control' {
        & $Dotnet run --project (Join-Path $repo 'tests/Desktop.Automation/Desktop.Automation.csproj') --configuration Release -- (Join-Path $appDir 'WiFiProxyPilot.exe') (Join-Path $OutputDirectory 'preview-uia')
        Assert ($LASTEXITCODE -eq 0) 'Actual preview UIA failed'
    }
    Test 'First activation starts real user task/watcher, preserves original backup' {
        $config=Read-Configuration (Join-Path $repo 'config.json'); $config.SetupComplete=$true; $config.ManagementIntent='Monitoring'
        $configPath=Join-Path $OutputDirectory 'confirmed-config.json'; Write-JsonAtomic $configPath $config
        Run (Join-Path $appDir 'WiFiProxyPilot.exe') @('/install','/quiet','/setup-config',('"'+$configPath+'"')) | Out-Null
        $root=Get-InstalledRoot; Assert ([bool]$root) 'Backend not installed'; $install=Read-Install $root
        Assert ([bool](Get-OwnedTask $install)) 'Owned login task missing'
        Assert (Test-RestoreAllowed (Read-OriginalProxy $root) $original) 'First proxy backup differs from original'
        $script:firstBackupHash=(Get-FileHash -LiteralPath (Join-Path $root 'state/proxy-before-install.json') -Algorithm SHA256).Hash
    }
    Test 'Actual WPF automatic pause/resume and Check now reach independent Watcher' {
        & $Dotnet run --project (Join-Path $repo 'tests/Desktop.Automation/Desktop.Automation.csproj') --configuration Release -- (Join-Path $appDir 'WiFiProxyPilot.exe') (Join-Path $OutputDirectory 'installed-uia') --installed
        Assert ($LASTEXITCODE -eq 0) 'Actual installed UIA failed'
    }
    Test 'Real PowerShell failure is shown by the clicked WPF command without false success' {
        $exe=Join-Path $appDir 'WiFiProxyPilot.exe'; Run $exe @('/pause','/quiet') | Out-Null
        $root=Get-InstalledRoot; $manifest=Read-Install $root; Stop-OwnedWatcher $manifest
        $path=Join-Path $root 'state/installation.json'; $bytes=[IO.File]::ReadAllBytes($path)
        try {
            # Corrupt the disposable test's ownership marker. Actual Control.ps1 must reject
            # this before changing the Paused intent; no test flag bypasses ownership checks.
            $fault=[Text.Encoding]::UTF8.GetString($bytes).TrimStart([char]0xFEFF) | ConvertFrom-Json
            $fault.Product='FaultInjection.NonOwned'; Write-JsonAtomic $path $fault
            & $Dotnet run --project (Join-Path $repo 'tests/Desktop.Automation/Desktop.Automation.csproj') --configuration Release -- $exe (Join-Path $OutputDirectory 'failure-uia') --backend-failure
            Assert ($LASTEXITCODE -eq 0) 'Actual UI did not report the PowerShell ownership rejection correctly'
        } finally { [IO.File]::WriteAllBytes($path,$bytes) }
        Run $exe @('/resume','/quiet') | Out-Null
    }
    Test 'Pause persists, then actual WinINet on/off/port/bypass readback' {
        $exe=Join-Path $appDir 'WiFiProxyPilot.exe'; Run $exe @('/pause','/quiet') | Out-Null
        $root=Get-InstalledRoot; Assert ((Read-Configuration (Join-Path $root 'config.json')).ManagementIntent -eq 'Paused') 'Intent not persisted'
        foreach ($port in @(7890,7891)) {
            $target=[pscustomobject]@{Action='Enable';Server=('192.0.2.1:'+$port)}
            Set-TargetProxy $target | Out-Null; $actual=Read-SystemProxy
            Assert ($actual.Enable -and $actual.Server -eq $target.Server) 'WinINet enable/port readback failed'
            Assert ($actual.Bypass -split ';' -contains '<local>') 'Local bypass missing'
        }
        Set-TargetProxy ([pscustomobject]@{Action='Disable';Server=''}) | Out-Null; Assert (-not (Read-SystemProxy).Enable) 'Actual manual proxy disable failed'
        Assert (((Read-SystemProxy).Flags -band 12) -eq ($automaticBefore.Flags -band 12)) 'PAC/autodetect flags changed'
    }
    Test 'Production monitor decisions with injected network facts write and read actual WinINet' {
        $root=Get-InstalledRoot; $config=Read-Configuration (Join-Path $root 'config.json')
        Assert ($config.ManagementIntent -eq 'Paused') 'Actual independent watcher must remain paused during injected-network verification'
        $cycleConfig=$config | ConvertTo-Json -Depth 12 | ConvertFrom-Json
        $cycleConfig.ManagementIntent='Monitoring'; $cycleConfig.Mode='Strict'; $cycleConfig.Diagnostics='None'; $cycleConfig.Port=7892; $cycleConfig.Whitelist=@('Fixture Bypass')
        $script:fixtureSsid='Fixture Ordinary'; $script:fixtureGateway='192.0.2.1'; $script:monitorEvidence=[Collections.Generic.List[object]]::new()
        $services=@{
            ReadNetwork={ [pscustomobject]@{Kind='Connected';Reason='Injected network facts';Generation=0;Candidates=@([pscustomobject]@{SSID=$script:fixtureSsid;Guid='11111111-1111-1111-1111-111111111111';Gateway=$script:fixtureGateway;Metric=10;Ready=$true;AddressKey='fixture';Matchable=$true})} }
            ReadProxy={ Read-SystemProxy }; ReadRegistry={ Get-ManualSnapshot }
            Apply={param($target) Set-TargetProxy $target}
            RecordApplied={param($snapshot) Write-JsonAtomic (Join-Path $root 'state/last-applied.json') $snapshot}
            IsStopping={ $false }; ReopenNative={}; Probe={ throw 'Diagnostics are disabled for this controlled test' }; Log={param($level,$message,$data)}
            Heartbeat={param($data) $script:monitorEvidence.Add([pscustomobject]$data)}
        }
        $state=New-MonitorState
        Invoke-AutomaticMonitorCycle $state $cycleConfig $services 0 | Out-Null
        Invoke-AutomaticMonitorCycle $state $cycleConfig $services 1 | Out-Null
        $actual=Read-SystemProxy; Assert ($actual.Enable -and $actual.Server -eq '192.0.2.1:7892') 'Production gateway decision did not enable the actual manual proxy'
        $script:fixtureGateway='192.0.2.2'
        Invoke-AutomaticMonitorCycle $state $cycleConfig $services 2 | Out-Null
        Invoke-AutomaticMonitorCycle $state $cycleConfig $services 3 | Out-Null
        Assert ((Read-SystemProxy).Server -eq '192.0.2.2:7892') 'Production gateway change did not update actual WinINet'
        $script:fixtureSsid='Fixture Bypass'
        Invoke-AutomaticMonitorCycle $state $cycleConfig $services 4 | Out-Null
        Invoke-AutomaticMonitorCycle $state $cycleConfig $services 5 | Out-Null
        Assert (-not (Read-SystemProxy).Enable) 'Production whitelist decision did not disable actual WinINet'
        Write-JsonAtomic (Join-Path $OutputDirectory 'injected-network-real-wininet.json') ([pscustomobject]@{NetworkInput='Synthetic facts, no physical Wi-Fi device or route change';ProxyBoundary='Actual Windows WinINet/registry';ProductionCode='Invoke-AutomaticMonitorCycle + Set-TargetProxy';Observations=$script:monitorEvidence})
    }
    Test 'Software upgrade preserves config, original backup and unique task ownership' {
        $root=Get-InstalledRoot; $before=[IO.File]::ReadAllBytes((Join-Path $root 'config.json')); Install
        Assert ((Get-FileHash -LiteralPath (Join-Path $root 'state/proxy-before-install.json')).Hash -eq $script:firstBackupHash) 'Original backup overwritten'
        Assert ([Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $root 'config.json'))) -eq [Convert]::ToBase64String($before)) 'Config changed during installer upgrade'
        Assert (@(Get-ScheduledTask | Where-Object TaskName -like 'WiFiProxySwitcher-*').Count -eq 1) 'Duplicate background tasks'
    }
    Test 'Uninstall conflict inspection is read-only and cancelled silent uninstall keeps installation' {
        $root=Get-InstalledRoot; $configHash=(Get-FileHash -LiteralPath (Join-Path $root 'config.json')).Hash
        Set-TargetProxy ([pscustomobject]@{Action='Enable';Server='198.51.100.2:8888'}) | Out-Null
        $conflict=Get-ManualSnapshot
        Run (Join-Path $appDir 'unins000.exe') @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART') @(1,2) | Out-Null
        Assert (Test-Path -LiteralPath $arp) 'Cancelled uninstall removed ARP entry'
        Assert ((Get-FileHash -LiteralPath (Join-Path $root 'config.json')).Hash -eq $configHash) 'Cancel changed config/intent'
        Assert (Test-RestoreAllowed (Get-ManualSnapshot) $conflict) 'Cancel changed proxy'
    }
    Test 'Real uninstaller explicit restore removes owned tasks/ARP/shortcuts and retains recovery data' {
        Remove 'restore' 'no'
        Assert (-not (Test-Path -LiteralPath $arp)) 'ARP entry remains'
        Assert (-not (Test-Path -LiteralPath (Join-Path $appDir 'WiFiProxyPilot.exe'))) 'Program file remains'
        Assert (-not (Get-InstalledRoot)) 'Backend pointer remains'
        Assert (@(Get-ScheduledTask | Where-Object TaskName -like 'WiFiProxySwitcher-*').Count -eq 0) 'Watcher task remains'
        Assert (Test-RestoreAllowed (Get-ManualSnapshot) $original) 'Original manual proxy not restored'
        Assert (@(Get-ChildItem (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'WiFiProxyPilot-Retained') -Directory).Count -gt 0) 'Recovery data not retained'
    }
    Test 'Actual v3.2 release self-install upgrades through final Setup preserving user rules and backup' {
        Assert (-not (Get-InstalledRoot)) 'Prior test must uninstall before legacy scenario'
        $old=Join-Path $OutputDirectory 'WiFiProxySwitcher-v32.exe'
        Invoke-WebRequest -UseBasicParsing -Uri 'https://github.com/jeffxuu/WiFiProxyPilot/releases/download/v3.2.0-beta.1/WiFiProxySwitcher.exe' -OutFile $old
        $legacyConfig=Read-Configuration (Join-Path $repo 'config.json'); $legacyConfig.SetupComplete=$true; $legacyConfig.ManagementIntent='Monitoring'; $legacyConfig.TrayAutoStart=$false; $legacyConfig.Whitelist=@('Legacy Test SSID',' 空格网络 ')
        $legacyPath=Join-Path $OutputDirectory 'legacy-confirmed.json'; Write-JsonAtomic $legacyPath $legacyConfig
        $legacyRoot=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) ('Pilot-Legacy-Acceptance-'+[Guid]::NewGuid().ToString('N'))
        Run $old @('/install','/quiet','/install-dir',('"'+$legacyRoot+'"'),'/setup-config',('"'+$legacyPath+'"')) | Out-Null
        $root=Get-InstalledRoot; $backupHash=(Get-FileHash -LiteralPath (Join-Path $root 'state/proxy-before-install.json')).Hash
        $configBytes=[IO.File]::ReadAllBytes((Join-Path $root 'config.json')); $taskName=(Read-Install $root).TaskName
        Assert (Test-Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\WiFiProxySwitcher') 'Real legacy uninstall registration missing'
        Install 'en-US'
        Assert ((Get-InstalledRoot) -eq $root) 'Engine data root moved'
        Assert ((Get-FileHash -LiteralPath (Join-Path $root 'state/proxy-before-install.json')).Hash -eq $backupHash) 'Legacy original backup overwritten'
        Assert ([Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $root 'config.json'))) -eq [Convert]::ToBase64String($configBytes)) 'Legacy configuration changed'
        Assert ((Read-Install $root).TaskName -eq $taskName) 'Task ownership identity changed'
        Assert (-not (Test-Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\WiFiProxySwitcher')) 'Legacy ARP entry remains'
        Assert (@(Get-ScheduledTask | Where-Object TaskName -like 'WiFiProxySwitcher-*').Count -eq 1) 'Duplicate task after legacy upgrade'
        $legacyEvidence=[pscustomobject]@{OldExeSha256=(Get-FileHash $old).Hash;Root=$root;BackupSha256=$backupHash;TaskName=$taskName;Rules=(Read-Configuration (Join-Path $root 'config.json')).Whitelist}
        Write-JsonAtomic (Join-Path $OutputDirectory 'legacy-upgrade.json') $legacyEvidence
        Remove 'restore' 'no'; Assert (Test-RestoreAllowed (Get-ManualSnapshot) $original) 'Legacy upgraded uninstall did not restore original'
    }
} finally {
    # Keep bounded lifecycle diagnostics after the disposable runner is destroyed.
    try {
        $controlEvidence=Join-Path $OutputDirectory 'control-evidence'; [IO.Directory]::CreateDirectory($controlEvidence) | Out-Null
        $controlDirectory=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'WiFiProxySwitcher-Control'
        foreach ($name in @('installer-PrepareInstall-result.json','installer-CommitInstall-result.json','installer-InspectUninstall-result.json','installer-Uninstall-result.json','control-errors.log','commands.jsonl','desktop-errors.log')) {
            $source=Join-Path $controlDirectory $name
            if (Test-Path -LiteralPath $source -PathType Leaf) {
                Assert-PlainPath $source
                $lines=@(Get-Content -LiteralPath $source -Encoding UTF8 -Tail 500)
                [IO.File]::WriteAllText((Join-Path $controlEvidence $name),($lines -join [Environment]::NewLine),[Text.UTF8Encoding]::new($false))
            }
        }
    } catch { $failed++; $results.Add([pscustomobject]@{Name='Capture bounded lifecycle evidence';Passed=$false;Error=$_.Exception.Message}) }
    # Always restore the disposable runner's original manual proxy, even after a failed assertion.
    try { $root=Get-InstalledRoot; if ($root) { Stop-OwnedWatcher (Read-Install $root) }; Restore-ManualSnapshot $original } catch { $failed++; $results.Add([pscustomobject]@{Name='Final original proxy restore';Passed=$false;Error=$_.Exception.Message}) }
    $results.Add([pscustomobject]@{Name='Final original proxy restored';Passed=(Test-RestoreAllowed (Get-ManualSnapshot) $original)})
    $result=[pscustomobject]@{SetupSha256=(Get-FileHash -LiteralPath $Setup -Algorithm SHA256).Hash;Windows=([Environment]::OSVersion.VersionString);Session=[Diagnostics.Process]::GetCurrentProcess().SessionId;Boundary='Disposable GitHub-hosted Windows, actual Setup/WinINet/tasks/WPF';Total=$results.Count;Failed=$failed;Results=$results;RealWirelessDevice='NOT RUN - hosted runner has no physical Wi-Fi adapter'}
    Write-JsonAtomic (Join-Path $OutputDirectory 'installed-results.json') $result
}
if ($failed) { throw ($failed.ToString()+' installed acceptance case(s) failed') }

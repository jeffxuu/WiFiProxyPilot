#requires -Version 5.1
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$script:EngineProtocol=2
. (Join-Path $PSScriptRoot 'lib\Core.ps1')
. (Join-Path $PSScriptRoot 'lib\Windows.ps1')
. (Join-Path $PSScriptRoot 'lib\Lifecycle.ps1')
. (Join-Path $PSScriptRoot 'lib\Monitor.ps1')
$mutex=$null; $owned=$false; $exitCode=0; $c=$null; $script:WatcherNative=$null
try {
    Initialize-Windows
    $mutex=New-UserMutex 'Watcher'; $owned=Enter-Mutex $mutex
    if (-not $owned) { exit 0 }
    $install=Read-Install $PSScriptRoot
    if ($null -ne $install.PSObject.Properties['Phase'] -and $install.Phase -eq 'Uninstalling') { exit 0 }
    Read-OriginalProxy $PSScriptRoot | Out-Null
    $stateDir=Join-Path $PSScriptRoot 'state'; $stopFile=Join-Path $stateDir 'stop.request'
    $checkFile=Join-Path $stateDir 'check.request'
    if (Test-Path -LiteralPath $stopFile) { exit 0 }
    $configPath=Join-Path $PSScriptRoot 'config.json'
    # Persist a v1 migration once, including its old pause marker, before the reload loop hashes it.
    # Invalid files remain eligible for the established last-good fallback.
    $gate=New-ConfigurationMutex $configPath; $gateTaken=$false
    try {
        $gateTaken=Enter-Mutex $gate 5000; if (-not $gateTaken) { throw '配置正在保存，请稍后重试' }
        try {
            $raw=Read-ConfigurationBytes $configPath
            $legacy=([Text.UTF8Encoding]::new($false,$true).GetString($raw).TrimStart([char]0xFEFF)) | ConvertFrom-Json
            $migrated=Read-Configuration $configPath
            if ($null -eq $legacy.PSObject.Properties['SchemaVersion'] -or $legacy.SchemaVersion -ne 2) { Write-JsonAtomic $configPath $migrated ($configPath+'.previous') }
        } catch { Write-ControlFailure 'ConfigurationMigration' $_.Exception.Message }
    } finally { if ($gateTaken) { $gate.ReleaseMutex() }; $gate.Dispose() }
    $reload=New-ConfigurationReloadState $configPath; $c=$reload.Config
    Write-JsonAtomic (Join-Path $stateDir 'config-last-good.json') $c
    $runId=[Guid]::NewGuid().ToString('N')
    Write-JsonAtomic (Join-Path $stateDir 'status.json') @{Time=[DateTimeOffset]::Now.ToString('o');PID=$PID;RunId=$runId;Outcome='Starting';EngineVersion='3.3.0-beta.1';SchemaVersion=$c.SchemaVersion;ManagementIntent=$c.ManagementIntent;SetupComplete=$c.SetupComplete;Stable=$false}
    Write-SwitchLog $PSScriptRoot $c 'INFO' '监控已启动，当前交互用户身份' @{Mode=$c.Mode;PID=$PID;RunId=$runId}
    if ($reload.Fallback) { Write-SwitchLog $PSScriptRoot $c 'ERROR' '当前配置无效，使用有效备份；请修复配置' $null }
    $clock=[Diagnostics.Stopwatch]::StartNew(); $state=New-MonitorState
    $appliedRevision=''; $checkRequestId=''; $completedCheckRequestId=''
    $services=@{
        ReadNetwork={
            if ($null -eq $script:WatcherNative) {
                $script:WatcherNative=[WiFiProxy.Native]::new()
                if ($script:WatcherNative.NotificationError -ne 0) { Write-SwitchLog $PSScriptRoot $c 'WARN' 'WLAN 通知注册失败，使用轮询兜底' @{Error=$script:WatcherNative.NotificationError} }
            }
            Get-NetworkSnapshot $script:WatcherNative
        }
        ReopenNative={ if ($null -ne $script:WatcherNative) { $script:WatcherNative.Dispose(); $script:WatcherNative=$null } }
        ReadProxy={ Read-SystemProxy }
        ReadRegistry={ Get-ManualSnapshot }
        Apply={
            param($target)
            $writeGate=New-ConfigurationMutex $configPath; $writeTaken=$false
            try {
                $writeTaken=Enter-Mutex $writeGate 5000; if (-not $writeTaken) { throw '配置正在保存，稍后重新确认代理目标' }
                # A pause, rules save, fresh scan or uninstall that won the gate cancels this old decision.
                $currentBytes=Read-ConfigurationBytes $configPath
                $current=ConvertFrom-ConfigurationText ([Text.UTF8Encoding]::new($false,$true).GetString($currentBytes).TrimStart([char]0xFEFF))
                if ($current.ManagementIntent -ne 'Monitoring' -or -not $current.SetupComplete -or (Get-ConfigurationHash $currentBytes) -cne $reload.Revision -or (Test-Path -LiteralPath $checkFile) -or (Test-Path -LiteralPath $stopFile)) { return [pscustomobject]@{Changed=$false;Snapshot=$null;Cancelled=$true} }
                $written=Set-TargetProxy $target
                # Keep the conflict-protection record in the same critical section as the system write.
                if ($written.Changed) { Write-JsonAtomic (Join-Path $stateDir 'last-applied.json') $written.Snapshot }
                return $written
            } finally { if ($writeTaken) { $writeGate.ReleaseMutex() }; $writeGate.Dispose() }
        }
        RecordApplied={ param($snapshot) }
        Probe={ param($gateway,$config) Test-ProxyEndpoint $gateway $config }
        IsStopping={ Test-Path -LiteralPath $stopFile }
        Log={ param($level,$message,$data) Write-SwitchLog $PSScriptRoot $c $level $message $data }
        Heartbeat={
            param($data)
            if ($data.Stable -and $data.Target -notin @('Keep','Retry','SetupRequired')) { $script:appliedRevision=$reload.Revision; $script:completedCheckRequestId=$checkRequestId }
            $networkKind='Unknown'; $actualServer=''; $warning=''; $ruleReason=''; $reasonCode='Unknown'; $ruleCode='Unknown'
            if ($data.Contains('NetworkKind')) { $networkKind=$data.NetworkKind }
            if ($data.Contains('ActualServer')) { $actualServer=$data.ActualServer }
            if ($data.Contains('Warning')) { $warning=$data.Warning }
            if ($data.Contains('RuleReason')) { $ruleReason=$data.RuleReason }
            if ($data.Contains('ReasonCode')) { $reasonCode=$data.ReasonCode }
            if ($data.Contains('RuleCode')) { $ruleCode=$data.RuleCode }
            Write-JsonAtomic (Join-Path $stateDir 'status.json') @{Time=[DateTimeOffset]::Now.ToString('o');PID=$PID;RunId=$runId;EngineVersion='3.3.0-beta.1';SchemaVersion=$c.SchemaVersion;ManagementIntent=$c.ManagementIntent;SetupComplete=$c.SetupComplete;Outcome=$data.Target;NetworkKind=$networkKind;SSID=$data.SSID;InterfaceGuid=$data.InterfaceGuid;Gateway=$data.Gateway;ActualEnabled=$data.ActualEnabled;ActualServer=$actualServer;Stable=$data.Stable;Reason=$data.Reason;RuleReason=$ruleReason;ReasonCode=$reasonCode;RuleCode=$ruleCode;Warning=$warning;ConfigRevision=$reload.Revision;AppliedRevision=$script:appliedRevision;RequestedCheckRequestId=$checkRequestId;CheckRequestId=$script:completedCheckRequestId;Health=$state.Health.Health;Diagnostics=$c.Diagnostics;Mode=$c.Mode;PollSeconds=$c.PollSeconds;DiagnosticIntervalSeconds=$c.DiagnosticIntervalSeconds;HealthCheckedAt=$state.HealthChecked;ClockSeconds=$clock.Elapsed.TotalSeconds}
        }
    }
    try { Assert-ProxyPolicy } catch { & $services.Log 'WARN' '检测到代理管理策略，受限制的写入将拒绝执行' @{Error=$_.Exception.Message} }
    while (-not (& $services.IsStopping)) {
        $configStamp=Get-ConfigurationStamp $configPath
        $configurationChanged=Update-MonitorConfiguration $reload $configPath $state $services.Log
        $c=$reload.Config
        if ($configurationChanged) { $script:appliedRevision=''; Write-JsonAtomic (Join-Path $stateDir 'config-last-good.json') $c }
        if (Test-Path -LiteralPath $checkFile) {
            $checkBytes=Read-ConfigurationBytes $checkFile
            $request=([Text.Encoding]::UTF8.GetString($checkBytes).TrimStart([char]0xFEFF)) | ConvertFrom-Json
            $checkRequestId=''; if ($null -ne $request.PSObject.Properties['RequestId']) { $checkRequestId=[string]$request.RequestId }
            if ((Get-ConfigurationHash (Read-ConfigurationBytes $checkFile)) -ceq (Get-ConfigurationHash $checkBytes)) { Remove-Item -LiteralPath $checkFile -Force }
            Reset-MonitorEvaluation $state
            & $services.ReopenNative
        }
        $wait=[int]$c.PollSeconds*1000
        try {
            $cycle=Invoke-AutomaticMonitorCycle $state $c $services $clock.Elapsed.TotalSeconds
            if ($cycle.Stopped) { break }; $wait=$cycle.WaitMs
        } catch {
            $msg=$_.Exception.Message
            Write-MonitorFailure $state $services $msg $clock.Elapsed.TotalSeconds
        }
        $notified=Wait-MonitorSignal $wait $script:WatcherNative $services.IsStopping { (Test-Path -LiteralPath $checkFile) -or (Get-ConfigurationStamp $configPath) -cne $configStamp }
        if ($notified) { Wait-MonitorSignal ([int]$c.DebounceMilliseconds) $null $services.IsStopping | Out-Null }
    }
    Write-JsonAtomic (Join-Path $stateDir 'status.json') @{Time=[DateTimeOffset]::Now.ToString('o');PID=$PID;RunId=$runId;Outcome='Stopped';EngineVersion='3.3.0-beta.1';SchemaVersion=$c.SchemaVersion;ManagementIntent=$c.ManagementIntent;SetupComplete=$c.SetupComplete;Stable=$false}
    Write-SwitchLog $PSScriptRoot $c 'INFO' '监控按停止请求退出' $null
} catch {
    $exitCode=1; $failure=$_.Exception.Message
    Write-ControlFailure 'Watcher' $failure
} finally {
    if ($null -ne $script:WatcherNative) { $script:WatcherNative.Dispose() }
    if ($owned) { $mutex.ReleaseMutex() }
    if ($null -ne $mutex) { $mutex.Dispose() }
}
exit $exitCode

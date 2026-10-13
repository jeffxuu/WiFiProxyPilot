#requires -Version 5.1
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
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
    $reload=New-ConfigurationReloadState $configPath; $c=$reload.Config
    Write-JsonAtomic (Join-Path $stateDir 'config-last-good.json') $c
    $runId=[Guid]::NewGuid().ToString('N')
    Write-JsonAtomic (Join-Path $stateDir 'status.json') @{Time=[DateTimeOffset]::Now.ToString('o');PID=$PID;RunId=$runId;Outcome='Starting'}
    Write-SwitchLog $PSScriptRoot $c 'INFO' '监控已启动，当前交互用户身份' @{Mode=$c.Mode;PID=$PID;RunId=$runId}
    if ($reload.Fallback) { Write-SwitchLog $PSScriptRoot $c 'ERROR' '当前配置无效，使用有效备份；请修复配置' $null }
    $clock=[Diagnostics.Stopwatch]::StartNew(); $state=New-MonitorState
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
        Apply={ param($target) Set-TargetProxy $target }
        RecordApplied={ param($snapshot) Write-JsonAtomic (Join-Path $stateDir 'last-applied.json') $snapshot }
        Probe={ param($gateway,$config) Test-ProxyEndpoint $gateway $config }
        IsStopping={ Test-Path -LiteralPath $stopFile }
        IsPaused={ Test-Path -LiteralPath (Join-Path $stateDir 'pause.request') }
        Log={ param($level,$message,$data) Write-SwitchLog $PSScriptRoot $c $level $message $data }
        Heartbeat={ param($data) Write-JsonAtomic (Join-Path $stateDir 'status.json') @{Time=[DateTimeOffset]::Now.ToString('o');PID=$PID;RunId=$runId;Outcome=$data.Target;SSID=$data.SSID;InterfaceGuid=$data.InterfaceGuid;Gateway=$data.Gateway;ActualEnabled=$data.ActualEnabled;Stable=$data.Stable;Reason=$data.Reason;ConfigRevision=$reload.Revision;Health=$state.Health.Health;Diagnostics=$c.Diagnostics;Mode=$c.Mode;PollSeconds=$c.PollSeconds;DiagnosticIntervalSeconds=$c.DiagnosticIntervalSeconds;HealthCheckedAt=$state.HealthChecked;ClockSeconds=$clock.Elapsed.TotalSeconds} }
    }
    try { Assert-ProxyPolicy } catch { & $services.Log 'WARN' '检测到代理管理策略，受限制的写入将拒绝执行' @{Error=$_.Exception.Message} }
    $paused=$false; $pauseFile=Join-Path $stateDir 'pause.request'
    while (-not (& $services.IsStopping)) {
        $configStamp=Get-ConfigurationStamp $configPath
        $configurationChanged=Update-MonitorConfiguration $reload $configPath $state $services.Log
        $c=$reload.Config
        if ($configurationChanged) { Write-JsonAtomic (Join-Path $stateDir 'config-last-good.json') $c }
        if (Test-Path -LiteralPath $pauseFile) {
            $paused=$true
            Invoke-AutomaticMonitorCycle $state $c $services $clock.Elapsed.TotalSeconds | Out-Null
            Wait-MonitorSignal 500 $null $services.IsStopping | Out-Null
            continue
        }
        if ($paused) { $state=New-MonitorState; $paused=$false }
        if (Test-Path -LiteralPath $checkFile) { Remove-Item -LiteralPath $checkFile -Force }
        $wait=[int]$c.PollSeconds*1000
        try {
            $cycle=Invoke-MonitorCycle $state $c $services $clock.Elapsed.TotalSeconds
            if ($cycle.Stopped) { break }; $wait=$cycle.WaitMs
        } catch {
            $msg=$_.Exception.Message
            Write-MonitorFailure $state $services $msg $clock.Elapsed.TotalSeconds
        }
        $notified=Wait-MonitorSignal $wait $script:WatcherNative $services.IsStopping { (Test-Path -LiteralPath $checkFile) -or (Test-Path -LiteralPath $pauseFile) -or (Get-ConfigurationStamp $configPath) -cne $configStamp }
        if ($notified) { Wait-MonitorSignal ([int]$c.DebounceMilliseconds) $null $services.IsStopping | Out-Null }
    }
    Write-JsonAtomic (Join-Path $stateDir 'status.json') @{Time=[DateTimeOffset]::Now.ToString('o');PID=$PID;RunId=$runId;Outcome='Stopped'}
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

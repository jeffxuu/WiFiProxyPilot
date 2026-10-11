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
    $c=Read-Configuration (Join-Path $PSScriptRoot 'config.json')
    $runId=[Guid]::NewGuid().ToString('N')
    Write-JsonAtomic (Join-Path $stateDir 'status.json') @{Time=[DateTimeOffset]::Now.ToString('o');PID=$PID;RunId=$runId;Outcome='Starting'}
    Write-SwitchLog $PSScriptRoot $c 'INFO' '监控已启动，当前交互用户身份' @{Mode=$c.Mode;PID=$PID;RunId=$runId}
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
        Log={ param($level,$message,$data) Write-SwitchLog $PSScriptRoot $c $level $message $data }
        Heartbeat={ param($data) Write-JsonAtomic (Join-Path $stateDir 'status.json') @{Time=[DateTimeOffset]::Now.ToString('o');PID=$PID;RunId=$runId;Outcome=$data.Target;SSID=$data.SSID;InterfaceGuid=$data.InterfaceGuid;Gateway=$data.Gateway;ActualEnabled=$data.ActualEnabled;Stable=$data.Stable;Reason=$data.Reason} }
    }
    try { Assert-ProxyPolicy } catch { & $services.Log 'WARN' '检测到代理管理策略，受限制的写入将拒绝执行' @{Error=$_.Exception.Message} }
    while (-not (& $services.IsStopping)) {
        if (Test-Path -LiteralPath $checkFile) { Remove-Item -LiteralPath $checkFile -Force }
        $wait=[int]$c.PollSeconds*1000
        try {
            $cycle=Invoke-MonitorCycle $state $c $services $clock.Elapsed.TotalSeconds
            if ($cycle.Stopped) { break }; $wait=$cycle.WaitMs
        } catch {
            $msg=$_.Exception.Message
            Write-MonitorFailure $state $services $msg $clock.Elapsed.TotalSeconds
        }
        $notified=Wait-MonitorSignal $wait $script:WatcherNative $services.IsStopping { Test-Path -LiteralPath $checkFile }
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

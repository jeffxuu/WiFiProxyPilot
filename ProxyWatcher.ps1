#requires -Version 5.1
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'lib\Core.ps1')
. (Join-Path $PSScriptRoot 'lib\Windows.ps1')
$mutex=$null; $owned=$false; $native=$null; $exitCode=0; $c=$null
try {
    Initialize-Windows
    $mutex=New-UserMutex 'Watcher'; $owned=Enter-Mutex $mutex
    if (-not $owned) { exit 0 }
    $stateDir=Join-Path $PSScriptRoot 'state'
    $marker=Join-Path $stateDir 'installation.json'
    $stopFile=Join-Path $stateDir 'stop.request'
    if (-not (Test-Path -LiteralPath $marker)) { throw '请先安装，禁止直接运行未安装的监控程序' }
    $install=Get-Content -LiteralPath $marker -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($install.OwnerSid -cne (Get-UserSid)) { throw '安装所有者与当前用户不一致' }
    $c=Read-Configuration (Join-Path $PSScriptRoot 'config.json')
    Write-JsonAtomic (Join-Path $stateDir 'status.json') @{ Time=[DateTimeOffset]::Now.ToString('o'); PID=$PID; Outcome='Starting' }
    Write-SwitchLog $PSScriptRoot $c 'INFO' '监控已启动，当前用户身份；Strict/Safe 规则见配置' @{ Mode=$c.Mode; PID=$PID }
    try { Assert-ProxyPolicy } catch { Write-SwitchLog $PSScriptRoot $c 'WARN' '检测到代理管理策略，受限制的写入将拒绝执行' @{ Error=$_.Exception.Message } }
    $clock=[Diagnostics.Stopwatch]::StartNew()
    $stability=@{ Key=''; Since=0.0 }; $lastLog=''; $lastLogTime=-300.0; $fastSince=0.0
    $health='Unknown'; $healthKey=''; $healthChecked=-3600.0; $failures=0; $lastDiagnostic=''; $lastWarning=''
    while (-not (Test-Path -LiteralPath $stopFile)) {
        $wait=[int]$c.PollSeconds*1000
        try {
            if ($null -eq $native) {
                $native=[WiFiProxy.Native]::new()
                if ($native.NotificationError -ne 0) { Write-SwitchLog $PSScriptRoot $c 'WARN' 'WLAN 通知注册失败，使用轮询兜底' @{ Error=$native.NotificationError } }
            }
            $snapshot=Get-NetworkSnapshot $native
            $target=Get-Target $snapshot $c
            $key=@($target.Guid,$target.SSID,$target.Gateway) | ConvertTo-Json -Compress
            if ($key -cne $healthKey) { $healthKey=$key; $health='Unknown'; $healthChecked=-3600.0; $failures=0 }
            # Apply Strict rules before any diagnostic; a slow probe must not delay a gateway update.
            if ($c.Mode -eq 'Safe') { $target=Get-Target $snapshot $c $health }
            $stable=Get-StableTarget $stability $target $clock.Elapsed.TotalSeconds $c
            $actual=[WiFiProxy.Native]::ReadProxy()
            $warning=''
            if (($actual.Flags -band 12) -ne 0 -or $actual.Pac) { $warning='检测到 PAC/自动检测；保持原设置，应用实际选路可能优先使用 PAC/WPAD' }
            if ($warning -cne $lastWarning) { if ($warning) { Write-SwitchLog $PSScriptRoot $c 'WARN' $warning $null }; $lastWarning=$warning }
            $changed=$false
            if ($null -ne $stable -and -not (Test-TargetMatches $actual $stable)) {
                $latest=Get-Target (Get-NetworkSnapshot $native) $c $health
                $latestKey=@($latest.Action,$latest.SSID,$latest.Guid,$latest.Gateway,$latest.Server) | ConvertTo-Json -Compress
                if ($latestKey -cne $stability.Key) { $stability.Key=''; throw '写入前网络状态已变化，取消本次更新并重新检测' }
                $changed=Set-TargetProxy $stable
                # Record only after API and registry verification. A crash before this file is conservative: restoration asks for explicit force.
                Write-JsonAtomic (Join-Path $stateDir 'last-applied.json') (Get-ManualSnapshot)
                $actual=[WiFiProxy.Native]::ReadProxy()
            }
            Write-JsonAtomic (Join-Path $stateDir 'status.json') @{ Time=[DateTimeOffset]::Now.ToString('o'); PID=$PID; Outcome=$target.Action; SSID=$target.SSID; InterfaceGuid=$target.Guid; Gateway=$target.Gateway; ActualEnabled=$actual.Enable; Reason=$target.Reason }
            $safeServer='<已有代理地址省略>'
            if ($actual.Server -match '^([0-9]{1,3}\.){3}[0-9]{1,3}:[0-9]{1,5}$' -or -not $actual.Server) { $safeServer=$actual.Server }
            $data=[ordered]@{ SSID=$target.SSID; InterfaceGuid=$target.Guid; Gateway=$target.Gateway; Target=$target.Action; ActualEnabled=$actual.Enable; ActualServer=$safeServer; Changed=$changed; Stable=($null -ne $stable); Reason=$target.Reason }
            $signature=@($data.SSID,$data.InterfaceGuid,$data.Gateway,$data.Target,$data.ActualEnabled,$data.ActualServer,$data.Stable,$data.Reason) | ConvertTo-Json -Compress
            if ($changed -or $signature -cne $lastLog -or ($target.Action -eq 'Keep' -and $clock.Elapsed.TotalSeconds-$lastLogTime -ge 300)) {
                Write-SwitchLog $PSScriptRoot $c 'INFO' '网络与代理状态' $data
                $lastLog=$signature; $lastLogTime=$clock.Elapsed.TotalSeconds
            }
            if ($target.Action -eq 'Keep' -or $null -eq $stable) {
                if ($fastSince -eq 0) { $fastSince=$clock.Elapsed.TotalSeconds }
                if ($clock.Elapsed.TotalSeconds-$fastSince -lt $c.FastRetryWindowSeconds) { $wait=[int]$c.RetrySeconds*1000 }
                if ($null -eq $stable -and $target.Action -ne 'Keep') { $wait=[Math]::Min($wait,[int]$c.DebounceMilliseconds) }
            } else { $fastSince=0 }
            if ($target.Gateway -and (Test-GatewayIPv4 $target.Gateway) -and $target.SSID -and $target.Reason -ne '精确匹配代理关闭白名单' -and $c.Diagnostics -ne 'None' -and ($clock.Elapsed.TotalSeconds-$healthChecked -ge $c.DiagnosticIntervalSeconds)) {
                $probe=Test-ProxyEndpoint $target.Gateway $c
                # Do not accept a result from a Wi-Fi link that changed during the probe.
                $after=Get-Target (Get-NetworkSnapshot $native) $c
                if ($after.Guid -ceq $target.Guid -and $after.SSID -ceq $target.SSID -and $after.Gateway -ceq $target.Gateway) {
                    $healthChecked=$clock.Elapsed.TotalSeconds
                    if ($probe.Health -eq 'Unavailable') { $failures++ } else { $failures=0 }
                    $health=$probe.Health
                    if ($probe.Health -eq 'Unavailable' -and $failures -lt $c.SafeFailureThreshold) { $health='Unknown' }
                    $diag=@($healthKey,$probe.Health,$probe.Reason,($failures -ge $c.SafeFailureThreshold)) | ConvertTo-Json -Compress
                    if ($diag -cne $lastDiagnostic) { Write-SwitchLog $PSScriptRoot $c 'WARN' '代理连通性诊断（TCP 开放不等于 HTTP 代理可用）' @{ SSID=$target.SSID; InterfaceGuid=$target.Guid; Gateway=$target.Gateway; Health=$probe.Health; Reason=$probe.Reason; Mode=$c.Mode; ConsecutiveFailures=$failures }; $lastDiagnostic=$diag }
                    if ($c.Mode -eq 'Safe') { $wait=[Math]::Min($wait,1000) }
                } else { $health='Unknown'; $failures=0; $healthChecked=-3600.0; $wait=100 }
            }
        } catch {
            $msg=$_.Exception.Message
            if ($msg -cne $lastLog -or $clock.Elapsed.TotalSeconds-$lastLogTime -ge 300) { Write-SwitchLog $PSScriptRoot $c 'ERROR' '读取或应用失败，保留现状并重试' @{ Error=$msg }; $lastLog=$msg; $lastLogTime=$clock.Elapsed.TotalSeconds }
            $stability.Key=''
            if ($null -ne $native) { $native.Dispose(); $native=$null }
            Write-JsonAtomic (Join-Path $stateDir 'status.json') @{ Time=[DateTimeOffset]::Now.ToString('o'); PID=$PID; Outcome='Retry'; Reason=$msg }
        }
        if ($null -ne $native) { $notified=$native.Wait($wait); if ($notified) { Start-Sleep -Milliseconds ([int]$c.DebounceMilliseconds) } }
        else { Start-Sleep -Milliseconds $wait }
    }
    Write-SwitchLog $PSScriptRoot $c 'INFO' '监控按停止请求退出' $null
} catch {
    $exitCode=1
    if ($null -ne $c) { try { Write-SwitchLog $PSScriptRoot $c 'ERROR' '监控异常终止，任务计划程序将按策略重启' @{ Error=$_.Exception.Message } } catch {} }
} finally {
    if ($null -ne $native) { $native.Dispose() }
    if ($owned) { $mutex.ReleaseMutex() }
    if ($null -ne $mutex) { $mutex.Dispose() }
}
exit $exitCode

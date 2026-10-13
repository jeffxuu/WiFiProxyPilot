Set-StrictMode -Version 2.0

function New-ConfigurationReloadState([string]$Path) {
    $c=$null; $fallback=$false
    try { $c=Read-Configuration $Path } catch {
        $errorText=$_.Exception.Message
        foreach ($previous in @(($Path+'.previous'),(Join-Path (Split-Path $Path -Parent) 'state/config-last-good.json'))) {
            try { $c=Read-Configuration $previous; $fallback=$true; break } catch { }
        }
        if ($null -eq $c) { throw ('配置无效且没有有效备份: '+$errorText) }
    }
    # The first loop reads and hashes one snapshot. Do not associate a second read's hash with the first read's values.
    $revision=''
    return @{Config=$c;Revision=$revision;Attempted='';Fallback=$fallback}
}
function Update-MonitorConfiguration($Reload,[string]$Path,$MonitorState,[scriptblock]$Log) {
    try {
        $bytes=Read-ConfigurationBytes $Path
        $sha=[Security.Cryptography.SHA256]::Create()
        try { $revision=[BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-','') } finally { $sha.Dispose() }
        if ($revision -ceq $Reload.Revision -or $revision -ceq $Reload.Attempted) { return $false }
        $Reload.Attempted=$revision
        $candidate=ConvertFrom-ConfigurationText ([Text.UTF8Encoding]::new($false,$true).GetString($bytes).TrimStart([char]0xFEFF))
        $Reload.Config=$candidate; $Reload.Revision=$revision; $Reload.Fallback=$false
        $MonitorState.Stability.Key=''; $MonitorState.HealthKey=''; $MonitorState.Health=@{Health='Unknown';Failures=0}; $MonitorState.HealthChecked=-1.0e9
        $Reload.LastError=''
        & $Log 'INFO' '配置已热更新，将重新确认当前 Wi-Fi 和代理目标' @{ConfigRevision=$revision;WhitelistCount=$candidate.Whitelist.Count}
        return $true
    } catch {
        $message=$_.Exception.Message
        if (-not $Reload.ContainsKey('LastError') -or $Reload.LastError -cne $message) { & $Log 'ERROR' '配置更新被拒绝，保持最近一次有效配置' @{Error=$message}; $Reload.LastError=$message }
        return $false
    }
}
function Get-ConfigurationStamp([string]$Path) {
    $item=Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
    if ($null -eq $item) { return 'missing' }
    return ([string]$item.LastWriteTimeUtc.Ticks+':'+[string]$item.Length)
}
function New-MonitorState {
    return @{ Stability=@{Key='';Since=0.0}; Health=@{Health='Unknown';Failures=0}; HealthKey=''; HealthChecked=-1.0e9; LastTick=-1.0; FastSince=-1.0; LastLog=''; LastError=''; LastErrorTime=-1.0e9; LastLogTime=-1.0e9; LastDiagnostic=''; LastWarning='' }
}
function Get-ObservedTarget($Snapshot,$Config,[string]$Health='Unknown') {
    $target=Get-Target $Snapshot $Config $Health
    $generation=0L; if ($null -ne $Snapshot.PSObject.Properties['Generation']) { $generation=[long]$Snapshot.Generation }
    $addressKey=''
    if ($target.Guid -and $Snapshot.Kind -eq 'Connected') {
        $candidate=@($Snapshot.Candidates | Where-Object { $_.Guid -eq $target.Guid })
        if ($candidate.Count -eq 1 -and $null -ne $candidate[0].PSObject.Properties['AddressKey']) { $addressKey=$candidate[0].AddressKey }
    }
    $target | Add-Member NoteProperty ObservationKey (@($generation,$addressKey) | ConvertTo-Json -Compress)
    return $target
}
function Get-TargetIdentity($Target) {
    return (@($Target.Action,$Target.SSID,$Target.Guid,$Target.Gateway,$Target.Server,$Target.ObservationKey) | ConvertTo-Json -Compress)
}
function Get-HealthIdentity($Target) {
    return (@($Target.SSID,$Target.Guid,$Target.Gateway,$Target.ObservationKey) | ConvertTo-Json -Compress)
}

# Dependencies are explicit scriptblocks, so tests exercise this same production cycle without Windows writes.
function Invoke-AutomaticMonitorCycle($State,$Config,$Services,[double]$Now) {
    if (& $Services.IsPaused) {
        & $Services.Heartbeat @{Target='Paused';SSID='';InterfaceGuid='';Gateway='';ActualEnabled=$null;Stable=$false;Reason='自动切换已暂停，当前手动代理保持不变'}
        return [pscustomobject]@{WaitMs=500;Stopped=$false;Paused=$true}
    }
    return Invoke-MonitorCycle $State $Config $Services $Now
}
function Invoke-MonitorCycle($State,$Config,$Services,[double]$Now) {
    $wait=[int]$Config.PollSeconds*1000
    $gapLimit=[Math]::Max(30,2*$Config.PollSeconds+3*$Config.DiagnosticTimeoutMilliseconds/1000.0+$Config.DebounceMilliseconds/1000.0)
    if ($State.LastTick -ge 0 -and $Now-$State.LastTick -gt $gapLimit) {
        $State.Stability.Key=''; $State.HealthKey=''; $State.Health=@{Health='Unknown';Failures=0}; $State.HealthChecked=-1.0e9
        & $Services.Log 'INFO' '检测到长时间暂停，重新确认网络并废弃旧诊断结果' @{GapSeconds=($Now-$State.LastTick)}
    }
    $State.LastTick=$Now
    $snapshot=& $Services.ReadNetwork
    if ($null -ne $snapshot.PSObject.Properties['ReopenNative'] -and $snapshot.ReopenNative) { & $Services.ReopenNative }
    $base=Get-ObservedTarget $snapshot $Config
    if ($base.Action -ne 'Keep') {
        $key=Get-HealthIdentity $base
        if ($key -cne $State.HealthKey) { $State.HealthKey=$key; $State.Health=@{Health='Unknown';Failures=0}; $State.HealthChecked=-1.0e9 }
    }
    $target=Get-ObservedTarget $snapshot $Config $State.Health.Health
    # Include the event generation and local-address identity in stable confirmation.
    $identity=Get-TargetIdentity $target
    $stable=$null -ne (Get-StableTarget $State.Stability $target $Now $Config)
    $actual=& $Services.ReadProxy
    $reg=& $Services.ReadRegistry
    $warning=''
    if (($actual.Flags -band 12) -ne 0 -or $actual.Pac) { $warning='检测到 PAC/自动检测；保持原设置，应用实际选路可能优先使用 PAC/WPAD' }
    if ($warning -cne $State.LastWarning) { if ($warning) { & $Services.Log 'WARN' $warning $null }; $State.LastWarning=$warning }
    $changed=$false
    if ($stable -and (-not (Test-TargetMatches $actual $target) -or -not (Test-RegistryMatchesTarget $reg $target))) {
        if (& $Services.IsStopping) { return [pscustomobject]@{WaitMs=0;Stopped=$true} }
        $latest=Get-ObservedTarget (& $Services.ReadNetwork) $Config $State.Health.Health
        if ((Get-TargetIdentity $latest) -cne $identity) { $State.Stability.Key=''; throw '写入前网络状态已变化，取消更新并重新检测' }
        if (& $Services.IsStopping) { return [pscustomobject]@{WaitMs=0;Stopped=$true} }
        $applied=& $Services.Apply $target
        $changed=$applied.Changed
        if ($changed) { & $Services.RecordApplied $applied.Snapshot }
        $actual=& $Services.ReadProxy
        $reg=& $Services.ReadRegistry
        if (-not (Test-TargetMatches $actual $target) -or -not (Test-RegistryMatchesTarget $reg $target)) { throw '写入后代理再次偏离目标，稍后重试' }
    }
    $safeServer='<已有代理地址省略>'
    if ($actual.Server -match '^([0-9]{1,3}\.){3}[0-9]{1,3}:[0-9]{1,5}$' -or -not $actual.Server) { $safeServer=$actual.Server }
    $data=[ordered]@{SSID=$target.SSID;InterfaceGuid=$target.Guid;Gateway=$target.Gateway;Target=$target.Action;ActualEnabled=$actual.Enable;ActualServer=$safeServer;Changed=$changed;Stable=$stable;Reason=$target.Reason}
    & $Services.Heartbeat $data
    $signature=@($data.SSID,$data.InterfaceGuid,$data.Gateway,$data.Target,$data.ActualEnabled,$data.ActualServer,$data.Stable,$data.Reason) | ConvertTo-Json -Compress
    if ($changed -or $signature -cne $State.LastLog -or ($target.Action -eq 'Keep' -and $Now-$State.LastLogTime -ge 300)) {
        & $Services.Log 'INFO' '网络与代理状态' $data; $State.LastLog=$signature; $State.LastLogTime=$Now
    }
    if ($stable -and $State.LastError) {
        & $Services.Log 'INFO' '检测恢复，当前代理已与稳定目标一致' $null
        $State.LastError=''
    }
    if (-not $stable) {
        if ($State.FastSince -lt 0) { $State.FastSince=$Now }
        if ($Now-$State.FastSince -lt $Config.FastRetryWindowSeconds) { $wait=[Math]::Min($wait,[int]$Config.RetrySeconds*1000) }
        if ($target.Action -ne 'Keep') { $wait=[Math]::Min($wait,[int]$Config.DebounceMilliseconds) }
    } else { $State.FastSince=-1.0 }
    # Run diagnostics only after stable confirmation/application; Strict must not wait on a probe.
    if ($stable -and $base.Action -eq 'Enable' -and $Config.Diagnostics -ne 'None' -and $Now-$State.HealthChecked -ge $Config.DiagnosticIntervalSeconds -and -not (& $Services.IsStopping)) {
        $probe=& $Services.Probe $target.Gateway $Config
        $after=Get-ObservedTarget (& $Services.ReadNetwork) $Config
        if ($after.Action -eq 'Enable' -and (Get-HealthIdentity $after) -ceq $State.HealthKey) {
            $State.HealthChecked=$Now
            Update-ProxyHealth $State.Health $probe.Health $Config.SafeFailureThreshold
            $diag=@($State.HealthKey,$probe.Health,$probe.Reason,$State.Health.Health) | ConvertTo-Json -Compress
            $level='INFO'; if ($probe.Health -in @('Unavailable','Unknown')) { $level='WARN' }
            if ($diag -cne $State.LastDiagnostic) { & $Services.Log $level '代理连通性诊断（TCP 开放不等于 HTTP 代理可用）' @{SSID=$target.SSID;InterfaceGuid=$target.Guid;Gateway=$target.Gateway;Health=$probe.Health;EffectiveHealth=$State.Health.Health;Reason=$probe.Reason;Mode=$Config.Mode;ConsecutiveFailures=$State.Health.Failures}; $State.LastDiagnostic=$diag }
            if ($Config.Mode -eq 'Safe') { $wait=[Math]::Min($wait,1000) }
        } else { $State.Stability.Key=''; $State.HealthKey=''; $State.Health=@{Health='Unknown';Failures=0}; $State.HealthChecked=-1.0e9; $wait=100 }
    }
    return [pscustomobject]@{WaitMs=$wait;Stopped=$false}
}

function Write-MonitorFailure($State,$Services,[string]$Message,[double]$Now) {
    if ($Message -cne $State.LastError -or $Now-$State.LastErrorTime -ge 300) {
        & $Services.Log 'ERROR' '读取或应用失败，继续重试；请检查实际代理状态' @{Error=$Message}
        $State.LastError=$Message; $State.LastErrorTime=$Now
    }
    $State.Stability.Key=''
    & $Services.ReopenNative
    & $Services.Heartbeat @{Target='Retry';SSID='';InterfaceGuid='';Gateway='';ActualEnabled=$null;Stable=$false;Reason=$Message}
}

function Wait-MonitorSignal([int]$Milliseconds,$Native,[scriptblock]$IsStopping,[scriptblock]$IsCheckRequested=$null) {
    $timer=[Diagnostics.Stopwatch]::StartNew()
    while ($timer.ElapsedMilliseconds -lt $Milliseconds -and -not (& $IsStopping)) {
        if ($null -ne $IsCheckRequested -and (& $IsCheckRequested)) { return $true }
        $chunk=[Math]::Min(500,[Math]::Max(1,$Milliseconds-[int]$timer.ElapsedMilliseconds))
        if ($null -ne $Native) { if ($Native.Wait($chunk)) { return $true } }
        else { Start-Sleep -Milliseconds $chunk }
    }
    return $false
}

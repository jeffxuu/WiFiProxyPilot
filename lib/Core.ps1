Set-StrictMode -Version 2.0

function Read-ConfigurationBytes([string]$Path) {
    $stream=[IO.FileStream]::new($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
    $memory=[IO.MemoryStream]::new()
    try { if ($stream.Length -gt 1048576) { throw '配置文件过大' }; $stream.CopyTo($memory); return ,$memory.ToArray() }
    finally { $memory.Dispose(); $stream.Dispose() }
}
function Read-Configuration([string]$Path) {
    $bytes=Read-ConfigurationBytes $Path
    $text=[Text.UTF8Encoding]::new($false,$true).GetString($bytes).TrimStart([char]0xFEFF)
    $raw=$text | ConvertFrom-Json
    $c=ConvertFrom-ConfigurationText $text
    # The old marker is consulted only while migrating a configuration without a persisted intent.
    if ($null -eq $raw.PSObject.Properties['ManagementIntent'] -and (Test-Path -LiteralPath (Join-Path (Split-Path $Path -Parent) 'state/pause.request'))) { $c.ManagementIntent='Paused' }
    return $c
}
function ConvertFrom-ConfigurationText([string]$Text) {
    $c = $Text | ConvertFrom-Json
    $schema=1
    if ($null -ne $c.PSObject.Properties['SchemaVersion']) {
        if (-not [int]::TryParse([string]$c.SchemaVersion,[ref]$schema) -or $schema -notin @(1,2)) { throw '配置版本不受支持，请升级后台组件' }
    }
    if ($schema -eq 2 -and ($null -eq $c.PSObject.Properties['ManagementIntent'] -or $null -eq $c.PSObject.Properties['SetupComplete'])) { throw '配置缺少管理意图或首次设置确认' }
    if ($null -eq $c.PSObject.Properties['ManagementIntent']) { $c | Add-Member NoteProperty ManagementIntent 'Monitoring' }
    if ($null -eq $c.PSObject.Properties['SetupComplete']) { $c | Add-Member NoteProperty SetupComplete $true }
    if ($c.ManagementIntent -cnotin @('Monitoring','Paused','Direct') -or $c.SetupComplete -isnot [bool]) { throw '管理意图或首次设置确认无效' }
    if (-not $c.SetupComplete -and $c.ManagementIntent -ne 'Paused') { throw '首次设置完成前不能开启自动切换或改变代理' }
    $c | Add-Member NoteProperty SchemaVersion 2 -Force
    foreach ($name in @('Whitelist','Port','Mode','PollSeconds','DebounceMilliseconds','DisconnectConfirmSeconds','RetrySeconds','FastRetryWindowSeconds','PreferredInterfaceGuid','Diagnostics','DiagnosticIntervalSeconds','DiagnosticTimeoutMilliseconds','HttpProbeUrl','SafeFailureThreshold','LogMaxBytes','LogArchives')) {
        if ($null -eq $c.PSObject.Properties[$name]) { throw "配置缺少字段: $name" }
    }
    foreach ($rule in @(@('Port',1,65535),@('PollSeconds',1,300),@('DebounceMilliseconds',100,5000),@('DisconnectConfirmSeconds',1,30),@('RetrySeconds',1,30),@('FastRetryWindowSeconds',1,60),@('DiagnosticIntervalSeconds',5,3600),@('DiagnosticTimeoutMilliseconds',100,5000),@('SafeFailureThreshold',1,10),@('LogMaxBytes',16384,10485760),@('LogArchives',1,10))) {
        $v = $c.($rule[0]); $n = 0
        if (-not [int]::TryParse([string]$v,[ref]$n) -or $n -lt $rule[1] -or $n -gt $rule[2]) { throw "配置范围错误: $($rule[0])" }
        $c.($rule[0])=$n
    }
    if ($c.Mode -cnotin @('Strict','Safe') -or $c.Diagnostics -cnotin @('None','Tcp','Http')) { throw '模式配置错误' }
    if ($c.Whitelist -isnot [Array] -or @($c.Whitelist | Where-Object { $_ -isnot [string] -or [string]::IsNullOrEmpty($_) }).Count) { throw 'Wi-Fi 规则必须是 SSID 字符串数组（允许空列表）' }
    $names=[Collections.Generic.List[string]]::new()
    foreach ($ssid in @($c.Whitelist)) {
        if ([Text.UTF8Encoding]::new($false,$true).GetByteCount($ssid) -gt 32 -or $ssid -match '[\x00-\x1f\x7f-\x9f]') { throw 'SSID 应为 1–32 个 UTF-8 字节，不能含控制字符' }
        if (-not @($names | Where-Object { [string]::Equals($_,$ssid,[StringComparison]::OrdinalIgnoreCase) }).Count) { $names.Add($ssid) }
    }
    $c.Whitelist=$names.ToArray()
    foreach ($flag in @('LoginMonitor','TrayAutoStart','CloseToTray','MinimizeToTray')) {
        if ($null -ne $c.PSObject.Properties[$flag] -and $c.$flag -isnot [bool]) { throw ('设置必须是布尔值: '+$flag) }
    }
    if ($c.PreferredInterfaceGuid) { $g = [Guid]::Empty; if (-not [Guid]::TryParse($c.PreferredInterfaceGuid,[ref]$g)) { throw '接口 GUID 无效' } }
    if ($c.Diagnostics -eq 'Http') {
        $u = $null
        if (-not [Uri]::TryCreate($c.HttpProbeUrl,[UriKind]::Absolute,[ref]$u) -or $u.Scheme -ne 'http' -or $u.UserInfo -or $u.Query -or $u.Fragment) { throw 'HTTP 诊断必须配置不含凭据、查询或片段的 http URL' }
    }
    if ($c.Mode -eq 'Safe' -and $c.Diagnostics -eq 'None') { throw 'Safe 模式必须启用诊断' }
    return $c
}

function Test-GatewayIPv4([string]$Address) {
    if ($Address -notmatch '^(0|[1-9][0-9]{0,2})\.(0|[1-9][0-9]{0,2})\.(0|[1-9][0-9]{0,2})\.(0|[1-9][0-9]{0,2})$') { return $false }
    $ip = $null
    if (-not [Net.IPAddress]::TryParse($Address,[ref]$ip) -or $ip.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork) { return $false }
    $b = $ip.GetAddressBytes()
    return ($b[0] -ne 0 -and $b[0] -ne 127 -and $b[0] -lt 224 -and -not ($b[0] -eq 169 -and $b[1] -eq 254))
}

function Get-Target($Snapshot, $Config, [string]$Health = 'Unknown') {
    if ($Snapshot.Kind -eq 'Disconnected') { return [pscustomobject]@{ Action='Disable'; Server=''; SSID=''; Guid=''; Gateway=''; Reason='已确认 Wi-Fi 断开' } }
    if ($Snapshot.Kind -ne 'Connected') { return [pscustomobject]@{ Action='Keep'; Server=''; SSID=''; Guid=''; Gateway=''; Reason=$Snapshot.Reason } }
    $items = @($Snapshot.Candidates)
    if ($Config.PreferredInterfaceGuid) {
        $items = @($items | Where-Object { [Guid]$_.Guid -eq [Guid]$Config.PreferredInterfaceGuid })
        if ($items.Count -ne 1) { return [pscustomobject]@{ Action='Keep'; Server=''; SSID=''; Guid=''; Gateway=''; Reason='首选 Wi-Fi 接口尚未连接' } }
    } elseif ($items.Count -gt 1) {
        if (@($items | Where-Object { -not $_.Ready }).Count) { return [pscustomobject]@{ Action='Keep'; Server=''; SSID=''; Guid=''; Gateway=''; Reason='多个 Wi-Fi 接口尚未形成可靠路由' } }
        $items = @($items | Sort-Object Metric)
        if ($items[0].Metric -eq $items[1].Metric) { return [pscustomobject]@{ Action='Keep'; Server=''; SSID=''; Guid=''; Gateway=''; Reason='多个 Wi-Fi 接口路由成本相同，拒绝猜测' } }
        $items = @($items[0])
    }
    if ($items.Count -ne 1 -or [string]::IsNullOrEmpty($items[0].SSID)) { return [pscustomobject]@{ Action='Keep'; Server=''; SSID=''; Guid=''; Gateway=''; Reason='无法可靠识别 SSID' } }
    $n = $items[0]
    $t = [pscustomobject]@{ Action='Keep'; Server=''; SSID=$n.SSID; Guid=$n.Guid; Gateway=$n.Gateway; Reason='' }
    $matchable=$true; if ($null -ne $n.PSObject.Properties['Matchable']) { $matchable=$n.Matchable }
    foreach ($ssid in @($Config.Whitelist)) {
        if ($matchable -and [string]::Equals($ssid,$n.SSID,[StringComparison]::OrdinalIgnoreCase)) { $t.Action='Disable'; $t.Reason='精确匹配免代理 Wi-Fi 规则'; return $t }
    }
    if (-not $n.Ready -or -not (Test-GatewayIPv4 $n.Gateway)) {
        $t.Reason='IPv4 网关尚未就绪或路由歧义'
        if ($null -ne $n.PSObject.Properties['RouteError'] -and $n.RouteError) { $t.Reason += ': '+$n.RouteError }
        return $t
    }
    if ($Config.Mode -eq 'Safe' -and $Health -eq 'Unavailable') { $t.Action='Disable'; $t.Reason='Safe: 代理连续检测失败，恢复直连并继续检测'; return $t }
    $t.Action='Enable'; $t.Server=('{0}:{1}' -f $n.Gateway,$Config.Port); $t.Reason='当前 Wi-Fi 未命中免代理规则，使用其 IPv4 网关'; return $t
}

function Add-LocalBypass([string]$Value) {
    $parts = @($Value -split ';' | Where-Object { $_.Trim() })
    if (-not @($parts | Where-Object { [string]::Equals($_.Trim(),'<local>',[StringComparison]::OrdinalIgnoreCase) }).Count) { $parts += '<local>' }
    return ($parts -join ';')
}

function Test-TargetMatches($Actual,$Target) {
    if ($Target.Action -eq 'Keep') { return $true }
    if ($Target.Action -eq 'Disable') { return (-not $Actual.Enable) }
    return ($Actual.Enable -and $Actual.Server -ceq $Target.Server -and @($Actual.Bypass -split ';' | Where-Object { [string]::Equals($_.Trim(),'<local>',[StringComparison]::OrdinalIgnoreCase) }).Count -gt 0)
}

function Get-StableTarget($State,$Target,[double]$Now,$Config) {
    if ($Target.Action -eq 'Keep') { $State.Key=''; $State.Since=$Now; return $null }
    $observation=''; if ($null -ne $Target.PSObject.Properties['ObservationKey']) { $observation=$Target.ObservationKey }
    $key = @($Target.Action,$Target.SSID,$Target.Guid,$Target.Gateway,$Target.Server,$observation) | ConvertTo-Json -Compress
    if ($State.Key -cne $key) { $State.Key=$key; $State.Since=$Now; return $null }
    $delay = $Config.DebounceMilliseconds / 1000.0
    if (-not $Target.SSID) { $delay = $Config.DisconnectConfirmSeconds }
    if (($Now - $State.Since) -lt $delay) { return $null }
    return $Target
}

function Test-RestoreAllowed($Current,$LastApplied,[switch]$Force) {
    if ($Force) { return $true }
    if ($null -eq $LastApplied) { return $false }
    return (($Current | ConvertTo-Json -Depth 8 -Compress) -ceq ($LastApplied | ConvertTo-Json -Depth 8 -Compress))
}

function Assert-InteractiveIdentity([string]$Sid,[int]$SessionId) {
    if ($Sid -in @('S-1-5-18','S-1-5-19','S-1-5-20') -or $SessionId -le 0) { throw '必须在普通交互用户会话运行，拒绝 SYSTEM/服务会话的 HKCU' }
}
function ConvertTo-RecordTime($Value) {
    if ($Value -is [DateTimeOffset]) { return $Value }
    if ($Value -is [DateTime]) { return [DateTimeOffset]::new($Value) }
    return [DateTimeOffset]::Parse([string]$Value,[Globalization.CultureInfo]::InvariantCulture)
}
function Test-RecordField($Record,[string]$Name) {
    if ($null -eq $Record) { return $false }
    if ($Record -is [Collections.IDictionary]) { return $Record.Contains($Name) }
    return $null -ne $Record.PSObject.Properties[$Name]
}
function Assert-ManualSnapshot($Snapshot) {
    foreach ($name in @('ProxyEnable','ProxyServer','ProxyOverride')) {
        if (-not (Test-RecordField $Snapshot $name)) { throw '原代理备份缺少必要字段，拒绝写入' }
        $entry=$Snapshot.$name
        if (-not (Test-RecordField $entry 'Exists') -or $entry.Exists -isnot [bool] -or -not (Test-RecordField $entry 'Kind') -or -not (Test-RecordField $entry 'Value')) { throw '原代理备份结构损坏，拒绝写入' }
        if ($entry.Exists) {
            if ($name -eq 'ProxyEnable') {
                if ($entry.Kind -ne 'DWord' -or ($entry.Value -isnot [int] -and $entry.Value -isnot [long]) -or $entry.Value -notin @(0,1)) { throw '原 ProxyEnable 类型/值不受支持，拒绝写入' }
            } elseif ($entry.Kind -ne 'String' -or $entry.Value -isnot [string]) { throw '原代理字符串类型不受支持，拒绝写入' }
        }
    }
}
function Test-RegistryMatchesTarget($Snapshot,$Target) {
    if ($Target.Action -eq 'Keep') { return $true }
    $enable=0
    if ($Snapshot.ProxyEnable.Exists) {
        if ($Snapshot.ProxyEnable.Kind -ne 'DWord') { return $false }
        $enable=[int]$Snapshot.ProxyEnable.Value
    }
    if ($Target.Action -eq 'Disable') { return $enable -eq 0 }
    if ($enable -ne 1 -or -not $Snapshot.ProxyServer.Exists -or $Snapshot.ProxyServer.Kind -ne 'String' -or $Snapshot.ProxyServer.Value -cne $Target.Server -or -not $Snapshot.ProxyOverride.Exists -or $Snapshot.ProxyOverride.Kind -ne 'String') { return $false }
    return @($Snapshot.ProxyOverride.Value -split ';' | Where-Object { [string]::Equals($_.Trim(),'<local>',[StringComparison]::OrdinalIgnoreCase) }).Count -gt 0
}
function Update-ProxyHealth($State,[string]$Result,[int]$Threshold) {
    if ($Result -eq 'Unavailable') {
        $State.Failures=[Math]::Min($Threshold,$State.Failures+1)
        if ($State.Failures -ge $Threshold) { $State.Health='Unavailable' }
        elseif ($State.Health -ne 'Unavailable') { $State.Health='Unknown' }
    } elseif ($Result -in @('TcpOpen','HttpResponse')) {
        $State.Failures=0; $State.Health=$Result
    } else {
        $State.Failures=0
        # Unknown does not prove recovery of a service already confirmed unavailable.
        if ($State.Health -ne 'Unavailable') { $State.Health='Unknown' }
    }
}

function Write-JsonAtomic([string]$Path,$Value,[string]$BackupPath='') {
    $tmp = $Path + '.tmp.' + [Guid]::NewGuid().ToString('N')
    try {
        [IO.File]::WriteAllText($tmp,($Value | ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($true))
        for ($attempt=0;$attempt -lt 6;$attempt++) {
            try {
                if (Test-Path -LiteralPath $Path) { if ($BackupPath) { [IO.File]::Replace($tmp,$Path,$BackupPath) } else { [IO.File]::Replace($tmp,$Path,[NullString]::Value) } } else { [IO.File]::Move($tmp,$Path) }
                break
            } catch {
                # Retry a transient sharing/removal failure without deleting or truncating the valid destination.
                if ($attempt -eq 5 -or -not (Test-Path -LiteralPath $tmp)) { throw }
                Start-Sleep -Milliseconds (25*($attempt+1))
            }
        }
    } finally { if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force } }
}

function Get-ConfigurationHash([byte[]]$Bytes) {
    $sha=[Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($sha.ComputeHash($Bytes)).Replace('-','') } finally { $sha.Dispose() }
}
function New-ConfigurationMutex([string]$Path) {
    # Shared verbatim with ConfigurationStore.LockName; the interactive task and GUI share a session.
    $key=[Text.Encoding]::UTF8.GetBytes([IO.Path]::GetFullPath($Path).ToUpperInvariant())
    return [Threading.Mutex]::new($false,('Local\WiFiConfig-'+(Get-ConfigurationHash $key)))
}
function Set-ManagementIntent([string]$Root,[ValidateSet('Monitoring','Paused','Direct')][string]$Intent) {
    $path=Join-Path $Root 'config.json'; Assert-PlainPath $path
    $gate=New-ConfigurationMutex $path; $taken=$false
    try {
        $taken=Enter-Mutex $gate 5000
        if (-not $taken) { throw '配置正在被其他窗口保存，请稍后重试' }
        $c=Read-Configuration $path
        if (-not $c.SetupComplete -and $Intent -ne 'Paused') { throw '请先完成首次设置并确认 Windows 手动代理变更' }
        $c.ManagementIntent=$Intent
        Write-JsonAtomic $path $c ($path+'.previous')
        return $c
    } finally { if ($taken) { $gate.ReleaseMutex() }; $gate.Dispose() }
}

function Write-SwitchLog([string]$Root,$Config,[string]$Level,[string]$Message,$Data) {
    $dir = Join-Path $Root 'logs'; [IO.Directory]::CreateDirectory($dir) | Out-Null
    $path = Join-Path $dir 'watcher.jsonl'
    if ((Test-Path -LiteralPath $path) -and (Get-Item -LiteralPath $path).Length -ge $Config.LogMaxBytes) {
        $old = "$path.$($Config.LogArchives)"; if (Test-Path -LiteralPath $old) { Remove-Item -LiteralPath $old -Force }
        for ($i=$Config.LogArchives-1; $i -ge 1; $i--) { if (Test-Path -LiteralPath "$path.$i") { Move-Item -LiteralPath "$path.$i" -Destination "$path.$($i+1)" -Force } }
        Move-Item -LiteralPath $path -Destination "$path.1" -Force
    }
    $line = [ordered]@{ Time=[DateTimeOffset]::Now.ToString('o'); Level=$Level; Message=$Message; Data=$Data } | ConvertTo-Json -Compress -Depth 8
    [IO.File]::AppendAllText($path,$line+[Environment]::NewLine,[Text.UTF8Encoding]::new($true))
}

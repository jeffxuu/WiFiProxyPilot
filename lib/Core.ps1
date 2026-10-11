Set-StrictMode -Version 2.0

function Read-Configuration([string]$Path) {
    $c = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($name in @('Whitelist','Port','Mode','PollSeconds','DebounceMilliseconds','DisconnectConfirmSeconds','RetrySeconds','FastRetryWindowSeconds','PreferredInterfaceGuid','Diagnostics','DiagnosticIntervalSeconds','DiagnosticTimeoutMilliseconds','HttpProbeUrl','SafeFailureThreshold','LogMaxBytes','LogArchives')) {
        if ($null -eq $c.PSObject.Properties[$name]) { throw "配置缺少字段: $name" }
    }
    foreach ($rule in @(@('Port',1,65535),@('PollSeconds',1,300),@('DebounceMilliseconds',100,5000),@('DisconnectConfirmSeconds',1,30),@('RetrySeconds',1,30),@('FastRetryWindowSeconds',1,60),@('DiagnosticIntervalSeconds',5,3600),@('DiagnosticTimeoutMilliseconds',100,5000),@('SafeFailureThreshold',1,10),@('LogMaxBytes',16384,10485760),@('LogArchives',1,10))) {
        $v = $c.($rule[0]); $n = 0
        if (-not [int]::TryParse([string]$v,[ref]$n) -or $n -lt $rule[1] -or $n -gt $rule[2]) { throw "配置范围错误: $($rule[0])" }
    }
    if ($c.Mode -cnotin @('Strict','Safe') -or $c.Diagnostics -cnotin @('None','Tcp','Http')) { throw '模式配置错误' }
    if ($c.Whitelist -isnot [Array] -or @($c.Whitelist | Where-Object { $_ -isnot [string] -or [string]::IsNullOrEmpty($_) }).Count) { throw '白名单必须是非空 SSID 字符串数组' }
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
    foreach ($ssid in $Config.Whitelist) {
        if ([string]::Equals($ssid,$n.SSID,[StringComparison]::OrdinalIgnoreCase)) { $t.Action='Disable'; $t.Reason='精确匹配代理关闭白名单'; return $t }
    }
    if (-not $n.Ready -or -not (Test-GatewayIPv4 $n.Gateway)) { $t.Reason='IPv4 网关尚未就绪或路由歧义'; return $t }
    if ($Config.Mode -eq 'Safe' -and $Health -eq 'Unavailable') { $t.Action='Disable'; $t.Reason='Safe: 代理连续检测失败，恢复直连并继续检测'; return $t }
    $t.Action='Enable'; $t.Server=('{0}:{1}' -f $n.Gateway,$Config.Port); $t.Reason='非白名单 Wi-Fi 的当前 IPv4 网关'; return $t
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
    $key = @($Target.Action,$Target.SSID,$Target.Guid,$Target.Gateway,$Target.Server) | ConvertTo-Json -Compress
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

function Write-JsonAtomic([string]$Path,$Value) {
    $tmp = $Path + '.tmp.' + [Guid]::NewGuid().ToString('N')
    try {
        [IO.File]::WriteAllText($tmp,($Value | ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($true))
        if (Test-Path -LiteralPath $Path) { [IO.File]::Replace($tmp,$Path,[NullString]::Value) } else { [IO.File]::Move($tmp,$Path) }
    } finally { if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force } }
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

Set-StrictMode -Version 2.0
$script:ProxyKey = 'Software\Microsoft\Windows\CurrentVersion\Internet Settings'

function Initialize-Windows {
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw '此操作只能在 Windows 当前交互用户下运行' }
    if (-not [Environment]::Is64BitProcess) { throw '请使用 64 位 Windows PowerShell 5.1，原生互操作布局仅针对 x64' }
    if (-not ('WiFiProxy.Native' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'Native.cs') }
}
function Get-UserSid { return [Security.Principal.WindowsIdentity]::GetCurrent().User.Value }
function New-UserMutex([string]$Purpose) { return [Threading.Mutex]::new($false,('Global\WiFiProxySwitcher.'+(Get-UserSid)+'.'+$Purpose)) }
function Enter-Mutex($Mutex,[int]$Timeout=0) {
    try { return $Mutex.WaitOne($Timeout) } catch [Threading.AbandonedMutexException] { return $true }
}
function Assert-PlainPath([string]$Path) {
    $p=[IO.Path]::GetFullPath($Path)
    while ($p) {
        if ((Test-Path -LiteralPath $p) -and ((Get-Item -LiteralPath $p -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw '安装/控制路径含链接或联接点，拒绝沿链接读写或删除' }
        $parent=[IO.Path]::GetDirectoryName($p)
        if ($parent -eq $p) { break }; $p=$parent
    }
}

function Get-NetworkSnapshot($Native) {
    try {
        $links = @($Native.ReadWifi())
        if ($links.Count -eq 0) { return [pscustomobject]@{ Kind='Disconnected'; Candidates=@(); Reason='WLAN 枚举确认没有已连接 Wi-Fi' } }
        $items = @()
        foreach ($link in $links) {
            $adapters = @(Get-NetAdapter -IncludeHidden -ErrorAction Stop | Where-Object { ([Guid]$_.InterfaceGuid) -eq ([Guid]$link.Guid) })
            if ($adapters.Count -ne 1 -or -not $adapters[0].HardwareInterface -or $adapters[0].Status -ne 'Up') { throw 'WLAN GUID 对应物理网卡尚未就绪或无法唯一关联' }
            $index = $adapters[0].ifIndex
            $ips = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop | Where-Object { $_.InterfaceIndex -eq $index -and $_.AddressState -eq 'Preferred' -and (Test-GatewayIPv4 $_.IPAddress) })
            $ownIPs = @($ips | ForEach-Object { $_.IPAddress })
            $routes = @(Get-NetRoute -AddressFamily IPv4 -PolicyStore ActiveStore -ErrorAction Stop | Where-Object { $_.InterfaceIndex -eq $index -and $_.DestinationPrefix -eq '0.0.0.0/0' -and (Test-GatewayIPv4 $_.NextHop) -and $_.State -eq 'Alive' -and $_.ValidLifetime.TotalSeconds -gt 0 -and $_.NextHop -notin $ownIPs })
            $ifaces = @(Get-NetIPInterface -AddressFamily IPv4 -ErrorAction Stop | Where-Object { $_.InterfaceIndex -eq $index -and $_.ConnectionState -eq 'Connected' })
            $gateway=''; $metric=[int]::MaxValue; $ready=$false
            if ($ips.Count -gt 0 -and $routes.Count -gt 0 -and $ifaces.Count -eq 1) {
                $routes = @($routes | Sort-Object RouteMetric)
                $best = @($routes | Where-Object { $_.RouteMetric -eq $routes[0].RouteMetric })
                $hops = @($best.NextHop | Select-Object -Unique)
                if ($hops.Count -eq 1) { $gateway=$hops[0]; $metric=[long]$routes[0].RouteMetric+[long]$ifaces[0].InterfaceMetric; $ready=$true }
            }
            $items += [pscustomobject]@{ SSID=$link.SSID; Guid=$link.Guid; Index=$index; Gateway=$gateway; Metric=$metric; Ready=$ready }
        }
        return [pscustomobject]@{ Kind='Connected'; Candidates=$items; Reason='' }
    } catch { return [pscustomobject]@{ Kind='Unknown'; Candidates=@(); Reason=$_.Exception.Message } }
}

function Assert-ProxyPolicy {
    foreach ($hive in @([Microsoft.Win32.Registry]::CurrentUser,[Microsoft.Win32.Registry]::LocalMachine)) {
        foreach ($path in @('Software\Policies\Microsoft\Windows\CurrentVersion\Internet Settings','Software\Policies\Microsoft\Internet Explorer\Control Panel')) {
            $k=$hive.OpenSubKey($path)
            if ($null -ne $k) {
                try {
                    if ($k.GetValue('ProxySettingsPerUser',1) -eq 0 -or $k.GetValue('Proxy',0) -eq 1 -or $k.GetValue('AutoConfig',0) -eq 1 -or @($k.GetValueNames() | Where-Object { $_ -in @('ProxyEnable','ProxyServer','ProxyOverride','AutoConfigURL') }).Count) { throw '代理由组策略管理，停止写入并联系管理员' }
                } finally { $k.Dispose() }
            }
        }
    }
}

function Get-ManualSnapshot {
    $k=[Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($script:ProxyKey)
    try {
        $out=[ordered]@{}
        foreach ($name in @('ProxyEnable','ProxyServer','ProxyOverride')) {
            $exists=$null -ne $k -and $name -in $k.GetValueNames()
            $value=$null; $kind=$null
            if ($exists) { $value=$k.GetValue($name,$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames); $kind=$k.GetValueKind($name).ToString() }
            $out[$name]=[ordered]@{ Exists=$exists; Kind=$kind; Value=$value }
        }
        return [pscustomobject]$out
    } finally { if ($null -ne $k) { $k.Dispose() } }
}

function Set-TargetProxy($Target) {
    Assert-ProxyPolicy
    $before=[WiFiProxy.Native]::ReadProxy()
    if (Test-TargetMatches $before $Target) { return $false }
    $server=$before.Server; $bypass=$before.Bypass
    if ($Target.Action -eq 'Enable') { $server=$Target.Server; $bypass=Add-LocalBypass $bypass }
    [WiFiProxy.Native]::SetManual(($Target.Action -eq 'Enable'),$server,$bypass)
    $actual=[WiFiProxy.Native]::ReadProxy()
    $reg=Get-ManualSnapshot
    if (-not (Test-TargetMatches $actual $Target) -or [int]$reg.ProxyEnable.Value -ne [int]$actual.Enable -or ($actual.Enable -and ($reg.ProxyServer.Value -cne $server -or $reg.ProxyOverride.Value -cne $bypass))) { throw '代理 API / 注册表回读验证失败' }
    return $true
}

function Restore-ManualSnapshot($Snapshot) {
    Assert-ProxyPolicy
    $server=''; $bypass=''; $enabled=$false
    if ($Snapshot.ProxyServer.Exists) { $server=[string]$Snapshot.ProxyServer.Value }
    if ($Snapshot.ProxyOverride.Exists) { $bypass=[string]$Snapshot.ProxyOverride.Value }
    if ($Snapshot.ProxyEnable.Exists) { $enabled=[int]$Snapshot.ProxyEnable.Value -ne 0 }
    [WiFiProxy.Native]::SetManual($enabled,$server,$bypass)
    $k=[Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($script:ProxyKey)
    try {
        foreach ($name in @('ProxyEnable','ProxyServer','ProxyOverride')) {
            $entry=$Snapshot.$name
            if ($entry.Exists) { $k.SetValue($name,$entry.Value,[Enum]::Parse([Microsoft.Win32.RegistryValueKind],$entry.Kind)) } else { $k.DeleteValue($name,$false) }
        }
    } finally { $k.Dispose() }
    [WiFiProxy.Native]::Refresh()
    if (-not (Test-RestoreAllowed (Get-ManualSnapshot) $Snapshot)) { throw '恢复原代理注册表配置回读失败' }
    $actual=[WiFiProxy.Native]::ReadProxy()
    if ($actual.Enable -ne $enabled -or $actual.Server -cne $server -or $actual.Bypass -cne $bypass) { throw '恢复原代理 WinINet 回读失败' }
}

function Test-ProxyEndpoint([string]$Gateway,$Config) {
    $client=[Net.Sockets.TcpClient]::new(); $result='Unknown'; $reason=''
    try {
        $async=$client.BeginConnect($Gateway,[int]$Config.Port,$null,$null)
        try {
            if (-not $async.AsyncWaitHandle.WaitOne([int]$Config.DiagnosticTimeoutMilliseconds)) { $result='Unavailable'; $reason='TCP 连接超时' }
            else {
                $client.EndConnect($async); $result='TcpOpen'; $reason='TCP 端口开放；尚未验证 HTTP 代理协议'
                if ($Config.Diagnostics -eq 'Http') {
                    $stream=$client.GetStream(); $stream.ReadTimeout=[int]$Config.DiagnosticTimeoutMilliseconds; $stream.WriteTimeout=[int]$Config.DiagnosticTimeoutMilliseconds
                    $url=[Uri]$Config.HttpProbeUrl
                    $request='GET '+$url.AbsoluteUri+" HTTP/1.1`r`nHost: "+$url.Authority+"`r`nConnection: close`r`n`r`n"
                    $bytes=[Text.Encoding]::ASCII.GetBytes($request); $stream.Write($bytes,0,$bytes.Length)
                    # A bounded status-line read, with a total deadline (not an unbounded slow-drip read).
                    $deadline=[Diagnostics.Stopwatch]::StartNew(); $line=[Collections.Generic.List[byte]]::new()
                    while ($line.Count -lt 1024 -and $deadline.ElapsedMilliseconds -lt $Config.DiagnosticTimeoutMilliseconds) {
                        $stream.ReadTimeout=[Math]::Max(1,[int]$Config.DiagnosticTimeoutMilliseconds-[int]$deadline.ElapsedMilliseconds)
                        $b=$stream.ReadByte(); if ($b -lt 0 -or $b -eq 10) { break }; $line.Add([byte]$b)
                    }
                    $status=[Text.Encoding]::ASCII.GetString($line.ToArray())
                    if ($status -match '^HTTP/1\.[01] ([0-9]{3})(?: |\r|$)') {
                        $code=[int]$Matches[1]
                        if ($code -ge 200 -and $code -lt 400) { $result='HttpResponse'; $reason='显式 HTTP 代理请求返回成功状态；不代表所有目标或 HTTPS 都可用' }
                        elseif ($code -eq 407) { $result='Unavailable'; $reason='HTTP 代理需要认证，本工具不提供凭据' }
                        else { $result='Unknown'; $reason='HTTP 请求失败但无法区分目标站点与代理故障' }
                    } else { $result='Unavailable'; $reason='未收到有效 HTTP 状态行' }
                }
            }
        } finally { $async.AsyncWaitHandle.Close() }
    } catch [Net.Sockets.SocketException] { $result='Unavailable'; $reason='TCP 连接失败: '+$_.Exception.SocketErrorCode }
    catch [IO.IOException] { $result='Unavailable'; $reason='HTTP 代理协议检测超时或连接被关闭' }
    catch { $result='Unknown'; $reason='诊断异常: '+$_.Exception.GetType().Name }
    finally { $client.Dispose() }
    return [pscustomobject]@{ Health=$result; Reason=$reason }
}

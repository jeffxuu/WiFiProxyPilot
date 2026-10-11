#requires -Version 5.1
[CmdletBinding()]
param([string]$ResultPath='')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'lib/Core.ps1')
. (Join-Path $root 'lib/Windows.ps1')
. (Join-Path $root 'lib/Lifecycle.ps1')
. (Join-Path $root 'lib/Monitor.ps1')
$config=Read-Configuration (Join-Path $root 'config.json')
$script:results=[Collections.Generic.List[object]]::new()
function Check([bool]$Condition,[string]$Message='断言失败') { if (-not $Condition) { throw $Message } }
function Case([string]$Name,[scriptblock]$Body) {
    $caseClock=[Diagnostics.Stopwatch]::StartNew()
    try { & $Body; $script:results.Add([pscustomobject]@{ Name=$Name; Passed=$true; Error=''; DurationMilliseconds=$caseClock.ElapsedMilliseconds }); Write-Host ('PASS '+$Name) }
    catch { $script:results.Add([pscustomobject]@{ Name=$Name; Passed=$false; Error=$_.Exception.Message; DurationMilliseconds=$caseClock.ElapsedMilliseconds }); Write-Host ('FAIL '+$Name+': '+$_.Exception.Message) }
}
function Link([string]$Ssid='Other',[string]$Gateway='10.0.0.1',[long]$Metric=10,[string]$Guid='11111111-1111-1111-1111-111111111111') {
    return [pscustomobject]@{ SSID=$Ssid; Gateway=$Gateway; Metric=$Metric; Guid=$Guid; Ready=(Test-GatewayIPv4 $Gateway) }
}
function Snapshot($Links) { return [pscustomobject]@{ Kind='Connected'; Candidates=@($Links); Reason='' } }
function Actual([bool]$Enabled,[string]$Server='10.0.0.1:7890',[string]$Bypass='<local>') { return [pscustomobject]@{ Enable=$Enabled; Server=$Server; Bypass=$Bypass } }
function Clone-Config { return ($config | ConvertTo-Json | ConvertFrom-Json) }

foreach ($ssid in @('MC-Office','Meituan','mc-office','MEITUAN','MC-OFFICE','meituan')) {
    $captured=$ssid
    Case "白名单精确匹配 $ssid" { Check ((Get-Target (Snapshot (Link $captured)) $config).Action -eq 'Disable') }
}
foreach ($ssid in @('MC-Office-Guest','MC-Office-5G','Meituan-Guest','Other',' MC-Office','MC-Office ')) {
    $captured=$ssid
    Case "非白名单 $ssid" { Check ((Get-Target (Snapshot (Link $captured)) $config).Action -eq 'Enable') }
}
Case '普通 Wi-Fi A→B 更新网关，即使代理已开启' {
    $a=Get-Target (Snapshot (Link 'A' '10.0.0.1')) $config; $b=Get-Target (Snapshot (Link 'B' '192.168.2.1')) $config
    Check ($a.Server -eq '10.0.0.1:7890' -and $b.Server -eq '192.168.2.1:7890')
    Check (-not (Test-TargetMatches (Actual $true $a.Server) $b))
}
Case '普通→白名单→普通' {
    Check ((Get-Target (Snapshot (Link 'A')) $config).Action -eq 'Enable')
    Check ((Get-Target (Snapshot (Link 'MC-Office')) $config).Action -eq 'Disable')
    Check ((Get-Target (Snapshot (Link 'B')) $config).Action -eq 'Enable')
}
Case '确认断开与 SSID 权限失败区分' {
    Check ((Get-Target ([pscustomobject]@{ Kind='Disconnected' }) $config).Action -eq 'Disable')
    Check ((Get-Target ([pscustomobject]@{ Kind='Unknown'; Reason='ERROR_ACCESS_DENIED' }) $config).Action -eq 'Keep')
    Check ((Get-Target (Snapshot (Link '')) $config).Action -eq 'Keep')
}
foreach ($gateway in @('','::1','fe80::1%11','0.0.0.0','169.254.1.1','127.0.0.1','255.255.255.255','224.0.0.1','10.0.0.999','1.2.3','010.0.0.1','10.0.0.1:7890')) {
    $captured=$gateway
    Case "拒绝无效 IPv4 网关 [$gateway]" { Check (-not (Test-GatewayIPv4 $captured)); Check ((Get-Target (Snapshot (Link 'Other' $captured)) $config).Action -eq 'Keep') }
}
Case 'DHCP 网关延迟及同一 SSID 网关变化' {
    Check ((Get-Target (Snapshot (Link 'Other' '')) $config).Action -eq 'Keep')
    $a=Get-Target (Snapshot (Link 'Other' '10.209.152.119')) $config
    $b=Get-Target (Snapshot (Link 'Other' '10.209.152.120')) $config
    Check ($a.Server -eq '10.209.152.119:7890' -and $a.Server -ne $b.Server)
}
Case '多无线接口成本优先、同成本拒绝、缺失路由拒绝' {
    $a=Link 'A' '10.0.0.1' 30; $b=Link 'B' '192.168.0.1' 10 '22222222-2222-2222-2222-222222222222'
    Check ((Get-Target (Snapshot @($a,$b)) $config).SSID -eq 'B')
    $a.Metric=10; Check ((Get-Target (Snapshot @($a,$b)) $config).Action -eq 'Keep')
    $a.Ready=$false; Check ((Get-Target (Snapshot @($a,$b)) $config).Action -eq 'Keep')
    $c=Clone-Config; $c.PreferredInterfaceGuid=$b.Guid
    Check ((Get-Target (Snapshot @($a,$b)) $c).SSID -eq 'B')
    Check ((Get-Target (Snapshot $a) $c).Action -eq 'Keep')
}
Case 'Strict 不因端口失败改变规则；Safe 显式关闭' {
    Check ((Get-Target (Snapshot (Link)) $config 'Unavailable').Action -eq 'Enable')
    $c=Clone-Config; $c.Mode='Safe'
    Check ((Get-Target (Snapshot (Link)) $c 'Unavailable').Action -eq 'Disable')
    Check ((Get-Target (Snapshot (Link)) $c 'Unknown').Action -eq 'Enable')
    Check ((Get-Target (Snapshot (Link)) $c 'TcpOpen').Action -eq 'Enable')
}
Case '防抖与快速切换，最终状态只使用 B 网关' {
    $state=@{ Key=''; Since=0.0 }; $a=Get-Target (Snapshot (Link 'A')) $config; $b=Get-Target (Snapshot (Link 'B' '10.1.0.1')) $config
    Check ($null -eq (Get-StableTarget $state $a 0 $config))
    Check ($null -eq (Get-StableTarget $state $b 0.1 $config))
    Check ($null -eq (Get-StableTarget $state $a 0.2 $config))
    Check ($null -eq (Get-StableTarget $state $b 0.3 $config))
    Check ((Get-StableTarget $state $b 1.0 $config).Server -eq '10.1.0.1:7890')
}
Case '短暂断开不写入；权限失败中断确认；确认断开关闭' {
    $state=@{ Key=''; Since=0.0 }; $d=Get-Target ([pscustomobject]@{ Kind='Disconnected' }) $config
    Check ($null -eq (Get-StableTarget $state $d 0 $config)); Check ($null -eq (Get-StableTarget $state $d 1 $config))
    $unknown=Get-Target ([pscustomobject]@{ Kind='Unknown'; Reason='读取失败' }) $config
    Check ($null -eq (Get-StableTarget $state $unknown 1.1 $config))
    Check ($null -eq (Get-StableTarget $state $d 1.2 $config))
    Check ((Get-StableTarget $state $d 3.3 $config).Action -eq 'Disable')
}
Case '相同状态不重写；本地绕过与已有绕过列表保留' {
    $t=Get-Target (Snapshot (Link)) $config
    Check (Test-TargetMatches (Actual $true) $t)
    Check (-not (Test-TargetMatches (Actual $true '10.0.0.1:7890' 'example.test') $t))
    Check ((Add-LocalBypass 'example.test;<LOCAL>') -ceq 'example.test;<LOCAL>')
    Check ((Add-LocalBypass 'example.test') -ceq 'example.test;<local>')
}

# Inject native WLAN and structured NetTCPIP objects. No Windows API or registry writer is invoked.
$script:fixture=$null
function Get-NetAdapter { param([switch]$IncludeHidden,$ErrorAction) if ($script:fixture.Throw) { throw '模拟权限不足' }; $script:fixture.Adapters }
function Get-NetIPAddress { param($AddressFamily,$ErrorAction) if ($script:fixture.ContainsKey('IPsThrow') -and $script:fixture.IPsThrow) { throw 'NetTCPIP 查询失败' }; $script:fixture.IPs }
function Get-NetRoute { param($AddressFamily,$PolicyStore,$ErrorAction) $script:fixture.Routes }
function Get-NetIPInterface { param($AddressFamily,$ErrorAction) $script:fixture.Interfaces }
function Fixture {
    $guid='11111111-1111-1111-1111-111111111111'
    $script:fixture=@{
        Throw=$false
        Links=@([pscustomobject]@{ Guid=$guid; SSID='Other' })
        Adapters=@([pscustomobject]@{ InterfaceGuid=$guid; HardwareInterface=$true; Status='Up'; ifIndex=11 })
        IPs=@([pscustomobject]@{ InterfaceIndex=11; AddressState='Preferred'; IPAddress='10.209.152.209' })
        Routes=@([pscustomobject]@{ InterfaceIndex=11; DestinationPrefix='0.0.0.0/0'; NextHop='10.209.152.119'; RouteMetric=10; State='Alive'; ValidLifetime=[TimeSpan]::FromHours(1) })
        Interfaces=@([pscustomobject]@{ InterfaceIndex=11; ConnectionState='Connected'; InterfaceMetric=20 })
    }
    $fake=[pscustomobject]@{}; $fake | Add-Member ScriptMethod ReadWifi { return $script:fixture.Links }; return $fake
}
Case '真实采集逻辑注入：VPN/以太网/虚拟接口不污染 Wi-Fi 网关' {
    $fake=Fixture
    $script:fixture.Routes += [pscustomobject]@{ InterfaceIndex=99; DestinationPrefix='0.0.0.0/0'; NextHop='192.168.99.1'; RouteMetric=0; State='Alive'; ValidLifetime=[TimeSpan]::FromHours(1) }
    $t=Get-Target (Get-NetworkSnapshot $fake) $config
    Check ($t.Server -eq '10.209.152.119:7890')
}
Case '真实采集逻辑注入：自己的 IP、过期路由、IPv6 被排除' {
    $fake=Fixture
    $script:fixture.Routes[0].NextHop='10.209.152.209'; Check ((Get-Target (Get-NetworkSnapshot $fake) $config).Action -eq 'Keep')
    $script:fixture.Routes[0].NextHop='fe80::1%11'; Check ((Get-Target (Get-NetworkSnapshot $fake) $config).Action -eq 'Keep')
    $script:fixture.Routes[0].NextHop='10.209.152.119'; $script:fixture.Routes[0].ValidLifetime=[TimeSpan]::Zero
    Check ((Get-Target (Get-NetworkSnapshot $fake) $config).Action -eq 'Keep')
}
Case '真实采集逻辑注入：多默认路由成本与同成本歧义' {
    $fake=Fixture
    $script:fixture.Routes += [pscustomobject]@{ InterfaceIndex=11; DestinationPrefix='0.0.0.0/0'; NextHop='10.209.152.118'; RouteMetric=30; State='Alive'; ValidLifetime=[TimeSpan]::FromHours(1) }
    Check ((Get-Target (Get-NetworkSnapshot $fake) $config).Gateway -eq '10.209.152.119')
    $script:fixture.Routes[1].RouteMetric=10
    Check ((Get-Target (Get-NetworkSnapshot $fake) $config).Action -eq 'Keep')
}
Case '真实采集逻辑注入：无 Wi-Fi、网卡权限失败、虚拟 WLAN 防护' {
    $fake=Fixture; $script:fixture.Links=@(); Check ((Get-NetworkSnapshot $fake).Kind -eq 'Disconnected')
    $fake=Fixture; $script:fixture.Throw=$true; Check ((Get-NetworkSnapshot $fake).Kind -eq 'Unknown')
    $fake=Fixture; $script:fixture.Adapters[0].HardwareInterface=$false; Check ((Get-NetworkSnapshot $fake).Kind -eq 'Disconnected')
}
Case '恢复冲突保护及显式强制恢复' {
    $before=[pscustomobject]@{ ProxyEnable=[pscustomobject]@{ Exists=$true; Kind='DWord'; Value=0 } }
    $last=$before | ConvertTo-Json -Depth 8 | ConvertFrom-Json
    Check (Test-RestoreAllowed $before $last)
    $last.ProxyEnable.Value=1; Check (-not (Test-RestoreAllowed $before $last))
    Check (-not (Test-RestoreAllowed $before $null))
    Check (Test-RestoreAllowed $before $null -Force)
}
Case '实际 TCP 诊断：开放端口与连接拒绝' {
    if (-not ('ProbeServer' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'ProbeServer.cs') }
    $server=[ProbeServer]::new([NullString]::Value)
    $c=Clone-Config; $c.Diagnostics='Tcp'; $c.Port=$server.Port
    try { Check ((Test-ProxyEndpoint '127.0.0.1' $c).Health -eq 'TcpOpen') } finally { $server.Dispose() }
    Check ((Test-ProxyEndpoint '127.0.0.1' $c).Health -eq 'Unavailable')
}
Case '实际 HTTP 诊断：成功、认证要求、非 HTTP 与目标失败' {
    if (-not ('ProbeServer' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'ProbeServer.cs') }
    foreach ($pair in @(@("HTTP/1.1 200 OK`r`nContent-Length: 0`r`n`r`n",'HttpResponse'),@("HTTP/1.1 407 Proxy Authentication Required`r`n`r`n",'Unavailable'),@("not-http`r`n",'Unavailable'),@("HTTP/1.1 503 Failed`r`n`r`n",'Unknown'))) {
        $server=[ProbeServer]::new($pair[0]); $c=Clone-Config; $c.Diagnostics='Http'; $c.HttpProbeUrl='http://example.test/probe'; $c.Port=$server.Port
        try {
            $probe=Test-ProxyEndpoint '127.0.0.1' $c
            Check ($probe.Health -eq $pair[1]) ($probe | ConvertTo-Json -Compress)
            Check ($server.Request.StartsWith('GET http://example.test/probe HTTP/1.1'))
        } finally { $server.Dispose() }
    }
}
Case '所有 PowerShell 文件语法解析及 PS 5.1 常见不兼容语法检查' {
    foreach ($file in Get-ChildItem -LiteralPath $root -Recurse -Filter '*.ps1') {
        $tokens=$null; $errors=$null; $ast=[Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
        Check ($errors.Count -eq 0) ($file.Name+': '+($errors | Out-String))
        Check (-not @($tokens | Where-Object { [string]$_.Kind -in @('QuestionQuestion','QuestionQuestionEquals','QuestionDot','AndAnd','OrOr','QuestionMark') }).Count) ('PS 5.1 不兼容语法: '+$file.Name)
    }
}
Case 'C# 编译、Windows x64 原生结构布局' {
    if (-not ('WiFiProxy.Native' -as [type])) { Add-Type -Path (Join-Path $root 'lib/Native.cs') -CompilerOptions '/langversion:5' }
    foreach ($pair in @(@('InterfaceInfo',532),@('Connection',604),@('Option',16),@('OptionList',32))) {
        $type=[WiFiProxy.Native].GetNestedType($pair[0],[Reflection.BindingFlags]::NonPublic)
        Check ([Runtime.InteropServices.Marshal]::SizeOf([type]$type) -eq $pair[1]) ('ABI 布局错误: '+$pair[0])
    }
}
Case '单实例锁跨进程排他（使用测试命名锁，不启动真实监控）' {
    $name='WiFiProxyTest.'+[Guid]::NewGuid().ToString('N'); $m=[Threading.Mutex]::new($false,$name); $taken=$false
    try {
        $taken=Enter-Mutex $m; Check $taken
        $job=Start-Job -ScriptBlock { param($n) $m=[Threading.Mutex]::new($false,$n); try { $ok=$m.WaitOne(0); if ($ok) { $m.ReleaseMutex() }; return $ok } finally { $m.Dispose() } } -ArgumentList $name
        try { $done=$job | Wait-Job -Timeout 20; Check ($null -ne $done) '子进程锁测试超时'; $result=Receive-Job $job -ErrorAction Stop; Check ($result -eq $false) } finally { Remove-Job $job -Force }
    } finally { if ($taken) { $m.ReleaseMutex() }; $m.Dispose() }
}
Case '任务登录/异常重启/电源/静默启动契约静态检查（不声称实机通过）' {
    $control=Get-Content -LiteralPath (Join-Path $root 'Control.ps1') -Raw
    foreach ($text in @('-AtLogOn','-LogonType Interactive','-RunLevel Limited','-MultipleInstances IgnoreNew','-AllowStartIfOnBatteries','-DontStopIfGoingOnBatteries','-RestartCount 999','-ExecutionTimeLimit ([TimeSpan]::Zero)')) { Check ($control.Contains($text)) ('缺少: '+$text) }
    $vbs=Get-Content -LiteralPath (Join-Path $root 'SilentLauncher.vbs') -Raw
    Check ($vbs.Contains('shell.Run(command, 0, True)') -and $vbs.Contains('WScript.Quit result'))
    $watcher=Get-Content -LiteralPath (Join-Path $root 'ProxyWatcher.ps1') -Raw
    Check ($watcher.Contains('Wait-MonitorSignal $wait'))
    foreach ($bat in Get-ChildItem -LiteralPath (Join-Path $root 'tools') -Filter '*.bat') { $text=Get-Content -LiteralPath $bat.FullName -Raw; Check ($text.Contains('DisableDelayedExpansion') -and ($text.Contains('"%~dp0..\Control.ps1"') -or $text.Contains('"%~dp0..\Diagnose.ps1"'))) }
}
Case 'UTF-8 BOM/中文空格路径与原子状态文件/日志轮转' {
    $temp=Join-Path ([IO.Path]::GetTempPath()) ('WiFi 测试 '+[Guid]::NewGuid().ToString('N')); [IO.Directory]::CreateDirectory($temp) | Out-Null
    try {
        $p=Join-Path $temp '状态.json'; Write-JsonAtomic $p @{Text='中文'}; Write-JsonAtomic $p @{Text='再次中文'}
        Check ((Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json).Text -eq '再次中文')
        $c=Clone-Config; $c.LogMaxBytes=128; $c.LogArchives=2
        for ($i=0;$i -lt 20;$i++) { Write-SwitchLog $temp $c 'INFO' '轮转模拟测试' @{ Number=$i; SSID='中文 Wi-Fi' } }
        Check (@(Get-ChildItem -LiteralPath (Join-Path $temp 'logs')).Count -le 3)
        $line=Get-Content -LiteralPath (Join-Path $temp 'logs/watcher.jsonl') -Encoding UTF8 | Select-Object -Last 1
        Check (($line | ConvertFrom-Json).Data.Number -eq 19)
    } finally { Remove-Item -LiteralPath $temp -Recurse -Force }
}
Case '配置错误被拒绝，不进行系统写入' {
    $temp=Join-Path ([IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString('N')+'.json')
    try {
        $c=Clone-Config; $c.Port=0; Write-JsonAtomic $temp $c; $rejected=$false
        try { Read-Configuration $temp | Out-Null } catch { $rejected=$true }; Check $rejected
        $c=Clone-Config; $c.Mode='Safe'; $c.Diagnostics='None'; Write-JsonAtomic $temp $c; $rejected=$false
        try { Read-Configuration $temp | Out-Null } catch { $rejected=$true }; Check $rejected
    } finally { if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force } }
}
. (Join-Path $PSScriptRoot 'Round2.Tests.ps1')
. (Join-Path $PSScriptRoot 'TaskOwnership.Tests.ps1')
. (Join-Path $PSScriptRoot 'Productization.Tests.ps1')
$failed=@($script:results | Where-Object { -not $_.Passed }).Count
$report=[pscustomobject]@{ Time=[DateTimeOffset]::Now.ToString('o'); Platform=[Environment]::OSVersion.Platform.ToString(); PowerShell=$PSVersionTable.PSVersion.ToString(); Total=$script:results.Count; Passed=$script:results.Count-$failed; Failed=$failed; Results=$script:results.ToArray(); RealWindowsIntegration='NOT RUN by this simulation suite' }
if ($ResultPath) { Write-JsonAtomic ([IO.Path]::GetFullPath($ResultPath)) $report }
Write-Host ("Tests: {0}, Passed: {1}, Failed: {2}" -f $report.Total,$report.Passed,$failed)
if ($failed) { exit 1 }; exit 0

# Loaded by Run-Tests.ps1; this file never invokes Windows writes or real task registration.
function Registry-Snapshot([bool]$Enabled,[string]$Server='10.0.0.1:7890',[string]$Bypass='<local>') {
    return [pscustomobject][ordered]@{
        ProxyEnable=[pscustomobject][ordered]@{Exists=$true;Kind='DWord';Value=[int]$Enabled}
        ProxyServer=[pscustomobject][ordered]@{Exists=$true;Kind='String';Value=$Server}
        ProxyOverride=[pscustomobject][ordered]@{Exists=$true;Kind='String';Value=$Bypass}
    }
}
function New-Harness {
    $script:h=@{
        Network=(Snapshot (Link)); Actual=[pscustomobject]@{Enable=$false;Server='old:80';Bypass='example.test';Flags=13;Pac='http://private.invalid/pac'}
        Registry=(Registry-Snapshot $false 'old:80' 'example.test'); Writes=0; Records=0; Probes=0; Logs=0; ReadCount=0; Reopens=0; Stopping=$false
        ProbeResult=[pscustomobject]@{Health='TcpOpen';Reason='TCP only'}; OnRead=$null; OnProbe=$null; OnApply=$null
    }
    return @{
        ReadNetwork={ $script:h.ReadCount++; if ($null -ne $script:h.OnRead) { & $script:h.OnRead $script:h.ReadCount }; $script:h.Network }
        ReadProxy={ $script:h.Actual }
        ReadRegistry={ $script:h.Registry }
        ReopenNative={ $script:h.Reopens++ }
        IsStopping={ $script:h.Stopping }
        Apply={ param($target)
            if ($null -ne $script:h.OnApply) { & $script:h.OnApply }
            $script:h.Writes++; $script:h.Actual.Enable=$target.Action -eq 'Enable'
            if ($script:h.Actual.Enable) { $script:h.Actual.Server=$target.Server; $script:h.Actual.Bypass=Add-LocalBypass $script:h.Actual.Bypass }
            $script:h.Registry=Registry-Snapshot $script:h.Actual.Enable $script:h.Actual.Server $script:h.Actual.Bypass
            [pscustomobject]@{Changed=$true;Snapshot=$script:h.Registry}
        }
        RecordApplied={ param($snapshot) $script:h.Records++; Check (Test-RestoreAllowed $snapshot $script:h.Registry) }
        Probe={ param($gateway,$c) $script:h.Probes++; if ($null -ne $script:h.OnProbe) { & $script:h.OnProbe }; $script:h.ProbeResult }
        Log={ param($level,$message,$data) $script:h.Logs++ }
        Heartbeat={ param($data) $script:h.LastHeartbeat=$data }
    }
}
function Cycle($State,$Services,[double]$Time,$C=$config) { Invoke-MonitorCycle $State $C $Services $Time | Out-Null }

Case 'R2 SSID 匹配在土耳其文化下仍严格完整匹配' {
    $old=[Threading.Thread]::CurrentThread.CurrentCulture
    try { [Threading.Thread]::CurrentThread.CurrentCulture=[Globalization.CultureInfo]::GetCultureInfo('tr-TR'); Check ((Get-Target (Snapshot (Link 'mc-office')) $config).Action -eq 'Disable'); Check ((Get-Target (Snapshot (Link 'MC-OFFICE-X')) $config).Action -eq 'Enable') }
    finally { [Threading.Thread]::CurrentThread.CurrentCulture=$old }
}
Case 'R2 WLAN 句柄错误要求重建，权限错误不当断网' {
    $fake=[pscustomobject]@{}; $fake | Add-Member ScriptMethod ReadWifi { throw 'ERROR_INVALID_HANDLE / ERROR_ACCESS_DENIED' }
    $snap=Get-NetworkSnapshot $fake; Check ($snap.Kind -eq 'Unknown' -and $snap.ReopenNative)
    $services=New-Harness; $script:h.Network=$snap; $state=New-MonitorState
    Cycle $state $services 0; Check ($script:h.Reopens -eq 1 -and $script:h.Writes -eq 0)
    $script:h.Network=Snapshot (Link); Cycle $state $services 1; Cycle $state $services 2; Check ($script:h.Writes -eq 1)
}
Case 'R2 WLAN 前后夹读拒绝 SSID A 与 B 路由混合' {
    $fake=Fixture; $script:linkReads=0
    $fake | Add-Member ScriptMethod ReadWifi { $script:linkReads++; if ($script:linkReads -eq 2) { $script:fixture.Links[0].SSID='Changed' }; $script:fixture.Links } -Force
    # Return independent link values, like real native ReadWifi, not mutable shared test references.
    $fake | Add-Member ScriptMethod ReadWifi { $script:linkReads++; $ssid='A'; if ($script:linkReads -ge 2) {$ssid='B'}; [pscustomobject]@{Guid=$script:fixture.Links[0].Guid;SSID=$ssid} } -Force
    Check ((Get-NetworkSnapshot $fake).Kind -eq 'Unknown')
}
Case 'R2 采集期间地址变化事件使快照失效' {
    $fake=Fixture; $fake | Add-Member NoteProperty Generation 0
    $fake | Add-Member ScriptMethod ReadWifi { $this.Generation++; $script:fixture.Links } -Force
    Check ((Get-NetworkSnapshot $fake).Kind -eq 'Unknown')
}
Case 'R2 白名单 SSID 已知但 NetTCPIP 查询失败仍能关闭' {
    $fake=Fixture; $script:fixture.Links[0].SSID='MC-Office'; $script:fixture.IPsThrow=$true
    $snap=Get-NetworkSnapshot $fake
    Check ($snap.Kind -eq 'Connected' -and (Get-Target $snap $config).Action -eq 'Disable')
    $script:fixture.Links[0].SSID='Other'; $t=Get-Target (Get-NetworkSnapshot $fake) $config
    Check ($t.Action -eq 'Keep' -and $t.Reason.Contains('NetTCPIP'))
}
Case 'R2 虚拟 WLAN 不阻挡真实 WLAN；任何本机接口 IP 均不能作网关' {
    $fake=Fixture; $g='22222222-2222-2222-2222-222222222222'
    $script:fixture.Links += [pscustomobject]@{Guid=$g;SSID='Virtual'}
    $script:fixture.Adapters += [pscustomobject]@{InterfaceGuid=$g;HardwareInterface=$false;Status='Up';ifIndex=22}
    Check ((Get-Target (Get-NetworkSnapshot $fake) $config).Gateway -eq '10.209.152.119')
    $script:fixture.IPs += [pscustomobject]@{InterfaceIndex=99;AddressState='Preferred';IPAddress='10.209.152.119'}
    Check ((Get-Target (Get-NetworkSnapshot $fake) $config).Action -eq 'Keep')
}
Case 'R2 SYSTEM 与服务会话在接触 HKCU 前被拒绝' {
    foreach ($pair in @(@('S-1-5-18',1),@('S-1-5-19',1),@('S-1-5-20',1),@('S-1-5-21-1',0))) {
        $caught=$false; try { Assert-InteractiveIdentity $pair[0] $pair[1] } catch { $caught=$true }; Check $caught
    }
    Assert-InteractiveIdentity 'S-1-5-21-1' 1
}
Case 'R2 完整生产循环在首次写入之前不执行诊断' {
    $services=New-Harness; $state=New-MonitorState
    Cycle $state $services 0; Check ($script:h.Writes -eq 0 -and $script:h.Probes -eq 0)
    $script:h.OnProbe={ Check ($script:h.Writes -eq 1) 'Strict 首次应用被诊断阻塞' }
    Cycle $state $services 1; Check ($script:h.Writes -eq 1 -and $script:h.Probes -eq 1 -and $script:h.Records -eq 1)
}
Case 'R2 仅注册表漂移也必须纠正，API 缓存一致不足以跳过' {
    $services=New-Harness; $state=New-MonitorState; Cycle $state $services 0; Cycle $state $services 1
    $script:h.Registry.ProxyServer.Value='192.168.99.1:7890'
    Cycle $state $services 2
    Check ($script:h.Writes -eq 2 -and $script:h.Registry.ProxyServer.Value -eq '10.0.0.1:7890')
}
Case 'R2 写入前切换网络或停止请求不会写旧状态' {
    $services=New-Harness; $state=New-MonitorState; Cycle $state $services 0
    $script:h.OnRead={param($n) if ($n -eq 3) { $script:h.Network=Snapshot (Link 'B' '192.168.2.1') }}
    $caught=$false; try { Cycle $state $services 1 } catch { $caught=$true }; Check ($caught -and $script:h.Writes -eq 0)
    $services=New-Harness; $state=New-MonitorState; Cycle $state $services 0; $script:h.Stopping=$true
    $r=Invoke-MonitorCycle $state $config $services 1; Check ($r.Stopped -and $script:h.Writes -eq 0)
}
Case 'R2 Safe 连续失败后锁定直连，Unknown 不假装恢复' {
    $services=New-Harness; $state=New-MonitorState; $c=Clone-Config; $c.Mode='Safe'; $c.DiagnosticIntervalSeconds=5
    $script:h.ProbeResult=[pscustomobject]@{Health='Unavailable';Reason='refused'}
    Cycle $state $services 0 $c; Cycle $state $services 1 $c; Check $script:h.Actual.Enable
    Cycle $state $services 6 $c; Cycle $state $services 7 $c; Cycle $state $services 8 $c; Check (-not $script:h.Actual.Enable)
    $script:h.ProbeResult=[pscustomobject]@{Health='Unknown';Reason='origin 503'}
    Cycle $state $services 12 $c; Cycle $state $services 13 $c; Check (-not $script:h.Actual.Enable)
    $script:h.ProbeResult=[pscustomobject]@{Health='TcpOpen';Reason='open'}
    Cycle $state $services 18 $c; Cycle $state $services 19 $c; Cycle $state $services 20 $c; Check $script:h.Actual.Enable
}
Case 'R2 Strict 多次诊断失败与网络读取失败均不擅自改规则' {
    $services=New-Harness; $state=New-MonitorState; $c=Clone-Config; $c.DiagnosticIntervalSeconds=5
    $script:h.ProbeResult=[pscustomobject]@{Health='Unavailable';Reason='closed'}
    Cycle $state $services 0 $c; Cycle $state $services 1 $c; Cycle $state $services 6 $c; Check $script:h.Actual.Enable
    $script:h.Network=[pscustomobject]@{Kind='Unknown';Reason='permission denied'}
    Cycle $state $services 7 $c; Check ($script:h.Actual.Enable -and $script:h.Writes -eq 1)
}
Case 'R2 诊断过程中切换或同 SSID 新事件丢弃旧结果' {
    $services=New-Harness; $state=New-MonitorState; $c=Clone-Config; $c.Mode='Safe'; $c.SafeFailureThreshold=1
    $script:h.Network | Add-Member NoteProperty Generation 0
    $script:h.ProbeResult=[pscustomobject]@{Health='Unavailable';Reason='old network'}
    $script:h.OnProbe={ $script:h.Network.Generation=1 }
    Cycle $state $services 0 $c; Cycle $state $services 1 $c
    Check ($state.Health.Health -eq 'Unknown' -and $state.HealthChecked -lt 0)
}
Case 'R2 长时间暂停后重新防抖并重查诊断，不复用旧失败' {
    $services=New-Harness; $state=New-MonitorState
    Cycle $state $services 0; Cycle $state $services 1
    $state.Health.Health='Unavailable'; $script:h.Network=Snapshot (Link 'B' '10.1.0.1')
    Cycle $state $services 3600; Check ($script:h.Writes -eq 1 -and $state.Health.Health -eq 'Unknown')
    Cycle $state $services 3601; Check ($script:h.Actual.Server -eq '10.1.0.1:7890')
}
Case 'R2 PollSeconds=300 时停止仍可中断等待' {
    $timer=[Diagnostics.Stopwatch]::StartNew()
    $script:stopChecks=0
    $result=Wait-MonitorSignal 300000 $null { $script:stopChecks++; $script:stopChecks -gt 1 }
    Check (-not $result -and $timer.ElapsedMilliseconds -lt 2000)
}
Case 'R2 HTTP 不完整状态行、LF-only、过长状态行不能当成功' {
    foreach ($text in @('HTTP/1.1 200 OK',"HTTP/1.1 200 OK`n",('HTTP/1.1 200 '+('X'*1100)+"`r`n"))) {
        $server=[ProbeServer]::new($text); $c=Clone-Config; $c.Port=$server.Port; $c.Diagnostics='Http'; $c.HttpProbeUrl='http://example.test/'
        try { Check ((Test-ProxyEndpoint '127.0.0.1' $c).Health -eq 'Unavailable') } finally { $server.Dispose() }
    }
}
Case 'R2 实际代理写入包装：Keep 不可写，回读失败不可记成功，策略拒绝不写' {
    $script:writeCalls=0; $script:denyPolicy=$false; $script:failReadback=$false
    $script:testActual=[pscustomobject]@{Enable=$false;Server='old:80';Bypass='example.test';Flags=13;Pac='private'}
    $script:testReg=Registry-Snapshot $false 'old:80' 'example.test'
    function Assert-ProxyPolicy { if ($script:denyPolicy) { throw 'policy' } }
    function Read-SystemProxy { $script:testActual }
    function Get-ManualSnapshot { $script:testReg }
    function Set-SystemManualProxy($enabled,$server,$bypass) {
        $script:writeCalls++; $script:testActual.Enable=$enabled; $script:testActual.Server=$server; $script:testActual.Bypass=$bypass
        if (-not $script:failReadback) { $script:testReg=Registry-Snapshot $enabled $server $bypass }
    }
    $t=Get-Target (Snapshot (Link)) $config
    $r=Set-TargetProxy $t; Check ($r.Changed -and $script:writeCalls -eq 1 -and $script:testActual.Bypass -eq 'example.test;<local>' -and $script:testActual.Pac -eq 'private')
    $r=Set-TargetProxy $t; Check (-not $r.Changed -and $script:writeCalls -eq 1)
    $script:testReg.ProxyServer.Value='drift'; $script:failReadback=$true
    $caught=$false; try { Set-TargetProxy $t | Out-Null } catch { $caught=$true }; Check $caught
    $before=$script:writeCalls; $script:denyPolicy=$true
    $caught=$false; try { Set-TargetProxy $t | Out-Null } catch { $caught=$true }; Check ($caught -and $script:writeCalls -eq $before)
    $script:denyPolicy=$false; $t.Action='Keep'; $caught=$false
    try { Set-TargetProxy $t | Out-Null } catch { $caught=$true }; Check ($caught -and $script:writeCalls -eq $before)
}

Case 'R2 压力：5000 次快速变化后收敛，不在不稳定期写代理' {
    $services=New-Harness; $state=New-MonitorState; $c=Clone-Config; $c.Diagnostics='None'; $timer=[Diagnostics.Stopwatch]::StartNew()
    for ($i=0;$i -lt 5000;$i++) {
        switch ($i % 5) {
            0 { $script:h.Network=Snapshot (Link 'MC-Office') }
            1 { $script:h.Network=Snapshot (Link 'A' '10.0.0.1') }
            2 { $script:h.Network=Snapshot (Link 'B' '192.168.2.1') }
            3 { $script:h.Network=[pscustomobject]@{Kind='Disconnected'} }
            4 { $script:h.Network=[pscustomobject]@{Kind='Unknown';Reason='DHCP delayed'} }
        }
        Cycle $state $services ($i/10.0) $c
    }
    Check ($script:h.Writes -eq 0)
    $script:h.Network=Snapshot (Link 'Final' '10.8.0.1'); Cycle $state $services 500 $c; Cycle $state $services 501 $c
    Check ($script:h.Writes -eq 1 -and $script:h.Actual.Server -eq '10.8.0.1:7890')
    Write-Host ('  5000 transitions: '+$timer.ElapsedMilliseconds+' ms')
}
Case 'R2 压力：3000 个稳定轮询仅写一次，日志不随轮询增长' {
    $services=New-Harness; $state=New-MonitorState; $c=Clone-Config; $c.Diagnostics='None'
    Cycle $state $services 0 $c
    for ($i=1;$i -le 3000;$i++) { Cycle $state $services ($i*5) $c }
    Check ($script:h.Writes -eq 1 -and $script:h.Records -eq 1 -and $script:h.Logs -eq 3)
    # Three records: PAC warning and the unstable/stable network states.
}
Case 'R2 压力：2000 次连续未知网络不写代理且只限频记日志' {
    $services=New-Harness; $state=New-MonitorState; $c=Clone-Config; $c.Diagnostics='None'
    $script:h.Network=[pscustomobject]@{Kind='Unknown';Reason='location denied'}
    for ($i=0;$i -lt 2000;$i++) { Cycle $state $services ($i*5) $c }
    Check ($script:h.Writes -eq 0 -and $script:h.Logs -le 36)
}
Case 'R2 压力：1000 条真实日志轮转和 300 次原子状态替换' {
    $temp=Join-Path ([IO.Path]::GetTempPath()) ('WiFi QA 中文 ! & [x] '+[Guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($temp) | Out-Null
    try {
        $c=Clone-Config; $c.LogMaxBytes=16384; $c.LogArchives=2
        for ($i=0;$i -lt 1000;$i++) { Write-SwitchLog $temp $c 'INFO' '压力测试' @{SSID='中文测试';Seq=$i} }
        $files=@(Get-ChildItem -LiteralPath (Join-Path $temp 'logs')); Check ($files.Count -le 3) ('日志文件数量异常: '+(($files | Select-Object Name,Length | ConvertTo-Json -Compress)))
        Check (($files | Measure-Object Length -Sum).Sum -lt 3*(16384+1024)) ('日志总长度异常: '+(($files | Select-Object Name,Length | ConvertTo-Json -Compress)))
        foreach ($file in $files) { foreach ($line in Get-Content -LiteralPath $file.FullName -Encoding UTF8) { $line | ConvertFrom-Json | Out-Null } }
        $p=Join-Path $temp 'state.json'
        for ($i=0;$i -lt 300;$i++) { Write-JsonAtomic $p @{Seq=$i}; Check ((Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json).Seq -eq $i) ('原子状态 Seq 不匹配: '+$i) }
        $temporaryFiles=@(Get-ChildItem -LiteralPath $temp | Where-Object { $_.Name -like '*.tmp.*' })
        Check ($temporaryFiles.Count -eq 0) ('临时文件残留: '+(@($temporaryFiles | ForEach-Object { $_.Name }) -join ','))
    } finally { Remove-TestFixture $temp }
}

function New-LifeFixture {
    $base=Join-Path ([IO.Path]::GetTempPath()) ('WiFi 生命周期 中文 & ! [1] '+[Guid]::NewGuid().ToString('N'))
    $source=Join-Path $base 'source'; $target=Join-Path $base 'installed'
    [IO.Directory]::CreateDirectory($source) | Out-Null
    foreach ($name in Get-ProductFiles) {
        $p=Join-Path $source $name; [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($p)) | Out-Null
        [IO.File]::WriteAllText($p,('test payload: '+$name))
    }
    Write-JsonAtomic (Join-Path $source 'config.json') (Clone-Config)
    $script:life=@{Base=$base;Source=$source;Root=$target;Pointer=$target;Task=$null;Stops=0;Restores=0;Protected=0;Unregistered=0;PointerAttempts=0;FailPointer=$false;Events=[Collections.Generic.List[string]]::new()}
}
$lifeMocks={
    function Get-UserSid { 'S-1-5-21-1-2-3-1001' }
    function Assert-ProxyPolicy {}
    function Protect-InstallDirectory([string]$Root) { $script:life.Protected++ }
    function Get-ManualSnapshot { Registry-Snapshot $false 'original:80' 'original.local' }
    function Get-OwnedTask($Manifest) { $script:life.Task }
    function Stop-OwnedWatcher($Manifest) { $script:life.Stops++; $script:life.Events.Add('stop'); [IO.File]::WriteAllText((Join-Path $Manifest.Root 'state/stop.request'),'stop') }
    function Restore-OwnedProxy($Manifest) { Check ($script:life.Stops -gt 0); $script:life.Restores++; $script:life.Events.Add('restore') }
    function Unregister-ScheduledTask { param($TaskName,$TaskPath,$Confirm,$ErrorAction) $script:life.Unregistered++; $script:life.Task=$null; $script:life.Events.Add('unregister') }
    function Get-InstalledRoot { $script:life.Pointer }
    function Remove-InstallPointer([string]$Root) { $script:life.PointerAttempts++; if ($script:life.FailPointer -and $script:life.PointerAttempts -eq 1) { throw '模拟指针删除失败' }; $script:life.Pointer=''; $script:life.Events.Add('pointer-removed') }
}
Case 'R2 安装真实文件流程：中文/空格/!/&/方括号与一次性备份' {
    New-LifeFixture; . $lifeMocks
    try {
        $m=Install-ProductFiles $script:life.Source $script:life.Root $null
        Check ((Test-Path -LiteralPath (Join-Path $script:life.Root 'lib/Monitor.ps1')) -and $script:life.Protected -eq 1)
        $before=Get-Content -LiteralPath (Join-Path $script:life.Root 'state/proxy-before-install.json') -Raw -Encoding UTF8
        $c=Read-Configuration (Join-Path $script:life.Root 'config.json'); $c.Mode='Safe'; Write-JsonAtomic (Join-Path $script:life.Root 'config.json') $c
        $oldHash=(@($m.Files | Where-Object { $_.Path -eq 'config.json' }))[0].Hash
        $updated=Install-ProductFiles $script:life.Source $script:life.Root $m
        Check ((Read-Configuration (Join-Path $script:life.Root 'config.json')).Mode -eq 'Safe')
        Check ((Get-Content -LiteralPath (Join-Path $script:life.Root 'state/proxy-before-install.json') -Raw -Encoding UTF8) -ceq $before)
        Check ((@($updated.Files | Where-Object { $_.Path -eq 'config.json' }))[0].Hash -ceq $oldHash)
        Uninstall-Product $updated | Out-Null
        Check (Test-Path -LiteralPath (Join-Path $script:life.Root 'config.json')) '重复安装不能把用户修改过的配置重新认领后删除'
    } finally { Remove-Item -LiteralPath $script:life.Base -Recurse -Force }
}
Case 'R2 缺文件或现有配置无效在停止与覆盖前失败' {
    New-LifeFixture; . $lifeMocks
    try {
        $m=Install-ProductFiles $script:life.Source $script:life.Root $null
        $file=Join-Path $script:life.Source 'lib/Monitor.ps1'; Remove-Item -LiteralPath $file -Force
        $caught=$false; try { Install-ProductFiles $script:life.Source $script:life.Root $m | Out-Null } catch { $caught=$true }
        Check ($caught -and $script:life.Stops -eq 0)
        [IO.File]::WriteAllText($file,'payload'); [IO.File]::WriteAllText((Join-Path $script:life.Root 'config.json'),'{invalid')
        $caught=$false; try { Install-ProductFiles $script:life.Source $script:life.Root $m | Out-Null } catch { $caught=$true }; Check ($caught -and $script:life.Stops -eq 0)
    } finally { Remove-Item -LiteralPath $script:life.Base -Recurse -Force }
}
Case 'R2 首次复制故障不留下无法重装的半安装目标' {
    New-LifeFixture; . $lifeMocks
    function Copy-ProductPayload([string]$Source,[string]$Root,[switch]$PreserveConfig) { [IO.File]::WriteAllText((Join-Path $Root 'partial'),'test'); throw '模拟复制故障' }
    try {
        $caught=$false; try { Install-ProductFiles $script:life.Source $script:life.Root $null | Out-Null } catch { $caught=$true }
        Check ($caught -and -not (Test-Path -LiteralPath $script:life.Root))
        Check (@(Get-ChildItem -LiteralPath $script:life.Base -Directory | Where-Object { $_.Name -like '*.stage.*' }).Count -eq 0)
    } finally { Remove-Item -LiteralPath $script:life.Base -Recurse -Force }
}
Case 'R2 卸载指针删除失败可重试，备份/标记保留且不再次覆盖代理' {
    New-LifeFixture; . $lifeMocks
    try {
        $m=Install-ProductFiles $script:life.Source $script:life.Root $null
        $script:life.Task=[pscustomobject]@{State='Ready'}; $script:life.FailPointer=$true
        [IO.File]::WriteAllText((Join-Path $script:life.Root '用户文件.txt'),'keep')
        $caught=$false; try { Uninstall-Product $m | Out-Null } catch { $caught=$true }
        Check ($caught -and (Test-Path -LiteralPath (Join-Path $script:life.Root 'state/installation.json')) -and (Test-Path -LiteralPath (Join-Path $script:life.Root 'state/proxy-before-install.json')))
        $retry=Get-Content -LiteralPath (Join-Path $script:life.Root 'state/installation.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        Uninstall-Product $retry | Out-Null
        Check ($script:life.Restores -eq 1 -and $script:life.Unregistered -eq 1 -and -not $script:life.Pointer)
        Check (Test-Path -LiteralPath (Join-Path $script:life.Root '用户文件.txt'))
        Check (-not (Test-Path -LiteralPath (Join-Path $script:life.Root 'state/installation.json')))
    } finally { Remove-Item -LiteralPath $script:life.Base -Recurse -Force }
}
Case 'R2 卸载在删除备份后中断也能继续，未知清单在变更前拒绝' {
    New-LifeFixture; . $lifeMocks
    try {
        $m=Install-ProductFiles $script:life.Source $script:life.Root $null
        $m.Files += [pscustomobject]@{Path='../outside.txt';Hash=('A'*64)}
        $caught=$false; try { Uninstall-Product $m | Out-Null } catch { $caught=$true }; Check ($caught -and $script:life.Stops -eq 0)
        $m.Files=@($m.Files | Where-Object { $_.Path -ne '../outside.txt' }); $m | Add-Member NoteProperty Phase 'Uninstalling'
        Remove-Item -LiteralPath (Join-Path $script:life.Root 'state/proxy-before-install.json') -Force
        Uninstall-Product $m | Out-Null
        Check ($script:life.Restores -eq 0 -and -not (Test-Path -LiteralPath (Join-Path $script:life.Root 'state/installation.json')))
    } finally { Remove-Item -LiteralPath $script:life.Base -Recurse -Force }
}
Case 'R2 恢复时注册表已等于备份仍必须刷新并验证 WinINet' {
    New-LifeFixture; . $lifeMocks
    # Reload only the real restoration function; other doubles remain local to this case.
    $tokens=$null; $errors=$null; $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'lib/Lifecycle.ps1'),[ref]$tokens,[ref]$errors)
    $fn=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Restore-OwnedProxy'},$true)
    . ([scriptblock]::Create($fn.Extent.Text))
    $script:restoreChecks=0
    function Restore-ManualSnapshot($Snapshot) { $script:restoreChecks++ }
    try {
        $m=Install-ProductFiles $script:life.Source $script:life.Root $null
        Restore-OwnedProxy $m | Out-Null
        Check ($script:restoreChecks -eq 1)
    } finally { Remove-Item -LiteralPath $script:life.Base -Recurse -Force }
}
Case 'R2 启动锁竞争回归与 50 次重复启动只有一次任务启动' {
    New-LifeFixture; [IO.Directory]::CreateDirectory((Join-Path $script:life.Root 'state')) | Out-Null
    $script:life.Held=$false; $script:life.Running=$false; $script:life.Starts=0; $script:life.Enabled=$false
    function Get-OwnedTask($Manifest) { [pscustomobject]@{State='Ready'} }
    function New-UserMutex($Purpose) {
        $m=[pscustomobject]@{}
        $m | Add-Member ScriptMethod WaitOne { param($timeout) if ($script:life.Running -or $script:life.Held) { return $false }; $script:life.Held=$true; return $true }
        $m | Add-Member ScriptMethod ReleaseMutex { $script:life.Held=$false }
        $m | Add-Member ScriptMethod Dispose {}
        return $m
    }
    function Enable-ScheduledTask { param($TaskName,$TaskPath,$ErrorAction) $script:life.Enabled=$true }
    function Start-ScheduledTask {
        param($TaskName,$TaskPath,$ErrorAction)
        Check (-not $script:life.Held) '父进程仍持有监控锁，真实子进程会误判为重复实例'
        $script:life.Starts++; $script:life.Running=$true
        Write-JsonAtomic (Join-Path $script:life.Root 'state/status.json') @{Time=[DateTimeOffset]::Now.ToString('o');RunId='new-run';Outcome='Enable'}
    }
    function Start-Sleep { param($Milliseconds) }
    try {
        $m=[pscustomobject]@{Root=$script:life.Root;TaskName='qa'}
        for ($i=0;$i -lt 50;$i++) { Start-OwnedWatcher $m | Out-Null }
        Check ($script:life.Starts -eq 1 -and $script:life.Enabled -and -not $script:life.Held)
    } finally { Remove-Item -LiteralPath $script:life.Base -Recurse -Force }
}
Case 'R2 停止时任务权限失败仍先发停止标志' {
    New-LifeFixture; [IO.Directory]::CreateDirectory((Join-Path $script:life.Root 'state')) | Out-Null
    function Get-OwnedTask($Manifest) { throw '任务访问被拒绝' }
    try {
        $caught=$false; try { Stop-OwnedWatcher ([pscustomobject]@{Root=$script:life.Root}) } catch { $caught=$true }
        Check ($caught -and (Test-Path -LiteralPath (Join-Path $script:life.Root 'state/stop.request')))
    } finally { Remove-Item -LiteralPath $script:life.Base -Recurse -Force }
}
Case 'R2 任务动作被篡改，即使名称/描述相同也不能启动或终止' {
    function Get-UserName { 'qa-user' }
    function Resolve-TaskUserSid([string]$UserId) { if ($UserId -ceq 'qa-user') { return 'qa-user' }; throw '未知测试账户' }
    function Get-WscriptPath { 'C:\Windows\System32\wscript.exe' }
    $m=[pscustomobject]@{OwnerSid='qa-user';Root='/tmp';TaskName='qa'}
    $t=[pscustomobject]@{Description='WiFiProxySwitcher-v1|qa-user|/tmp';Principal=[pscustomobject]@{UserId='qa-user';LogonType='Interactive';RunLevel='Limited'};Actions=@([pscustomobject]@{Execute=(Get-WscriptPath);Arguments='//B //Nologo ".\SilentLauncher.vbs" Watch';WorkingDirectory='/tmp'})}
    Assert-OwnedTaskDefinition $t $m
    $t.Actions[0].Execute='another-program.exe'; $caught=$false
    try { Assert-OwnedTaskDefinition $t $m } catch { $caught=$_.Exception.Message.Contains('动作') }; Check $caught
    $t.Actions[0].Execute=Get-WscriptPath; $t.Actions[0].Arguments='another-script.vbs'; $caught=$false
    try { Assert-OwnedTaskDefinition $t $m } catch { $caught=$_.Exception.Message.Contains('动作') }; Check $caught
    $t.Principal.RunLevel='Highest'; $caught=$false
    try { Assert-OwnedTaskDefinition $t $m } catch { $caught=$_.Exception.Message.Contains('权限') }; Check $caught
}
Case 'R2 心跳 DateTime/DateTimeOffset/ISO 字符串均保留毫秒和时区' {
    $stamp=[DateTimeOffset]::Parse('2026-10-12T08:09:10.1234567+08:00')
    Check ((ConvertTo-RecordTime $stamp).UtcTicks -eq $stamp.UtcTicks)
    Check ((ConvertTo-RecordTime $stamp.UtcDateTime).UtcTicks -eq $stamp.UtcTicks)
    Check ((ConvertTo-RecordTime $stamp.ToString('o')).UtcTicks -eq $stamp.UtcTicks)
    $roundtrip=@{Time=$stamp.ToString('o')} | ConvertTo-Json | ConvertFrom-Json
    Check ((ConvertTo-RecordTime $roundtrip.Time).UtcTicks -eq $stamp.UtcTicks)
}
Case 'R2 原生 SSID 解码使用实际字节长度，非 UTF-8 仍按非白名单处理' {
    $bytes=[Text.Encoding]::UTF8.GetBytes('MC-Office-Guest')
    $link=[WiFiProxy.Native]::DecodeSsid([Guid]::NewGuid(),$bytes,9)
    Check ($link.SSID -ceq 'MC-Office' -and $link.NameDecoded -and $link.SsidHex -ceq '4D432D4F6666696365')
    $bad=[WiFiProxy.Native]::DecodeSsid([Guid]::NewGuid(),[byte[]]@(255,254,253),3)
    Check (-not $bad.NameDecoded -and $bad.SsidHex -ceq 'FFFEFD')
    $n=Link $bad.SSID; $n | Add-Member NoteProperty Matchable $false
    $c=Clone-Config; $c.Whitelist=@($bad.SSID)
    Check ((Get-Target (Snapshot $n) $c).Action -eq 'Enable')
    foreach ($len in @(0,33)) { $caught=$false; try { [WiFiProxy.Native]::DecodeSsid([Guid]::NewGuid(),$bytes,$len) | Out-Null } catch {$caught=$true}; Check $caught }
}
Case 'R2 关闭代理保留注册表最新地址和绕过项，而非旧 API 缓存' {
    $script:testActual=[pscustomobject]@{Enable=$true;Server='old:80';Bypass='old.local';Flags=3;Pac=''}
    $script:testReg=Registry-Snapshot $true 'latest:7890' 'new.local'
    function Assert-ProxyPolicy {}
    function Read-SystemProxy { $script:testActual }
    function Get-ManualSnapshot { $script:testReg }
    function Set-SystemManualProxy($enabled,$server,$bypass) { $script:testActual.Enable=$enabled; $script:testActual.Server=$server; $script:testActual.Bypass=$bypass; $script:testReg=Registry-Snapshot $enabled $server $bypass }
    $t=Get-Target (Snapshot (Link 'MC-Office')) $config
    $result=Set-TargetProxy $t
    Check ($result.Changed -and -not $script:testActual.Enable -and $script:testActual.Server -ceq 'latest:7890' -and $script:testActual.Bypass -ceq 'new.local')
}
Case 'R2 实际恢复函数的冲突与显式 Force 参数传递' {
    $temp=Join-Path ([IO.Path]::GetTempPath()) ('WiFiRestore-'+[Guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory((Join-Path $temp 'state')) | Out-Null
    $original=Registry-Snapshot $false 'original:80'; $last=Registry-Snapshot $true; $script:external=Registry-Snapshot $true 'user-changed:80'
    $script:restored=0
    function Get-ManualSnapshot { $script:external }
    function Restore-ManualSnapshot($Snapshot) { $script:restored++ }
    try {
        Write-JsonAtomic (Join-Path $temp 'state/proxy-before-install.json') $original
        Write-JsonAtomic (Join-Path $temp 'state/last-applied.json') $last
        $caught=$false; try { Restore-OwnedProxy ([pscustomobject]@{Root=$temp}) | Out-Null } catch {$caught=$true}
        Check ($caught -and $script:restored -eq 0)
        Restore-OwnedProxy ([pscustomobject]@{Root=$temp}) -Force | Out-Null; Check ($script:restored -eq 1)
    } finally { Remove-Item -LiteralPath $temp -Recurse -Force }
}
Case 'R2 四个实际子进程并发争用锁，释放后才能取得所有权' {
    $name='WiFiProxyRound2.'+[Guid]::NewGuid().ToString('N'); $m=[Threading.Mutex]::new($false,$name); $owned=Enter-Mutex $m; $jobs=@()
    Check $owned
    try {
        for ($i=0;$i -lt 4;$i++) { $jobs += Start-Job -ScriptBlock {param($n) $m=[Threading.Mutex]::new($false,$n); try {$ok=$m.WaitOne(0); if($ok){$m.ReleaseMutex()}; $ok} finally {$m.Dispose()}} -ArgumentList $name }
        $jobs | Wait-Job -Timeout 30 | Out-Null
        foreach ($job in $jobs) { Check ($job.State -eq 'Completed') '锁竞争子进程未完成'; Check ((Receive-Job $job -ErrorAction Stop) -eq $false) }
        $m.ReleaseMutex(); $owned=$false
        $job=Start-Job -ScriptBlock {param($n) $m=[Threading.Mutex]::new($false,$n); try {$ok=$m.WaitOne(0); if($ok){$m.ReleaseMutex()}; $ok} finally {$m.Dispose()}} -ArgumentList $name
        $jobs += $job; $job | Wait-Job -Timeout 20 | Out-Null
        Check ($job.State -eq 'Completed' -and (Receive-Job $job -ErrorAction Stop) -eq $true)
    } finally { if($owned){$m.ReleaseMutex()}; $m.Dispose(); $jobs | Remove-Job -Force }
}
Case 'R2 只读诊断无代理或任务修改调用；VBS 使用相对脚本参数' {
    $t=$null; $e=$null; $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'Diagnose.ps1'),[ref]$t,[ref]$e)
    Check ($e.Count -eq 0)
    $calls=@($ast.FindAll({param($n) $n -is [Management.Automation.Language.CommandAst]},$true) | ForEach-Object {$_.GetCommandName()})
    foreach ($forbidden in @('Set-TargetProxy','Set-SystemManualProxy','Restore-ManualSnapshot','Register-ScheduledTask','Start-ScheduledTask','Stop-ScheduledTask','Unregister-ScheduledTask')) {Check ($forbidden -notin $calls)}
    $vbs=Get-Content -LiteralPath (Join-Path $root 'SilentLauncher.vbs') -Raw
    Check ($vbs.Contains('script = ".\ProxyWatcher.ps1"') -and $vbs.Contains('script = ".\Control.ps1"') -and $vbs.Contains('shell.CurrentDirectory = root'))
}
Case 'R2 原始注册表字典与 JSON 备份均可验证，损坏备份不能启用监控' {
    $ordered=[ordered]@{
        ProxyEnable=[ordered]@{Exists=$true;Kind='DWord';Value=0}
        ProxyServer=[ordered]@{Exists=$false;Kind=$null;Value=$null}
        ProxyOverride=[ordered]@{Exists=$false;Kind=$null;Value=$null}
    }
    Assert-ManualSnapshot ([pscustomobject]$ordered)
    Assert-ManualSnapshot ($ordered | ConvertTo-Json -Depth 5 | ConvertFrom-Json)
    $ordered.ProxyEnable.Value=$true
    $caught=$false; try { Assert-ManualSnapshot $ordered } catch {$caught=$true}; Check $caught
    New-LifeFixture; . $lifeMocks
    try {
        $m=Install-ProductFiles $script:life.Source $script:life.Root $null
        [IO.File]::WriteAllText((Join-Path $script:life.Root 'state/proxy-before-install.json'),'{}')
        $caught=$false; try { Install-ProductFiles $script:life.Source $script:life.Root $m | Out-Null } catch {$caught=$true}
        Check ($caught -and $script:life.Stops -eq 0)
    } finally { Remove-Item -LiteralPath $script:life.Base -Recurse -Force }
}
Case 'R2 升级前保存用户改过的脚本，未知新文件冲突拒绝覆盖' {
    New-LifeFixture; . $lifeMocks
    try {
        $m=Install-ProductFiles $script:life.Source $script:life.Root $null
        $edited=Join-Path $script:life.Root 'ProxyWatcher.ps1'; [IO.File]::WriteAllText($edited,'user customized watcher')
        Install-ProductFiles $script:life.Source $script:life.Root $m | Out-Null
        $backups=@(Get-ChildItem -LiteralPath (Join-Path $script:life.Root 'user-backups') -Recurse -File)
        Check ($backups.Count -eq 1 -and (Get-Content -LiteralPath $backups[0].FullName -Raw) -ceq 'user customized watcher')
        $before=$script:life.Stops; $m.Files=@($m.Files | Where-Object {$_.Path -ne 'Diagnose.ps1'})
        $caught=$false; try { Install-ProductFiles $script:life.Source $script:life.Root $m | Out-Null } catch {$caught=$true}
        Check ($caught -and $script:life.Stops -eq $before)
    } finally { Remove-Item -LiteralPath $script:life.Base -Recurse -Force }
}
Case 'R2 持续写入异常不会被成功的防抖轮次重置日志限频' {
    $services=New-Harness; $state=New-MonitorState; $c=Clone-Config; $c.Diagnostics='None'
    $script:h.OnApply={throw 'persistent policy denial'}
    for ($i=0;$i -lt 300;$i++) {
        try {Cycle $state $services ($i*5) $c} catch {Write-MonitorFailure $state $services $_.Exception.Message ($i*5)}
    }
    Check ($script:h.Writes -eq 0 -and $script:h.Logs -le 8)
    $script:h.OnApply=$null; Cycle $state $services 1500 $c; Cycle $state $services 1501 $c
    Check ($script:h.Writes -eq 1 -and -not $state.LastError)
}

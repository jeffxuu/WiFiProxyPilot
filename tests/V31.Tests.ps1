# Loaded by Run-Tests.ps1; every network, scheduler and proxy action remains simulated.
. (Join-Path $root 'lib/Core.ps1')
. (Join-Path $root 'lib/Monitor.ps1')
Case 'V31 内置规则无法由空用户名单或直接配置删除' {
    $c=Clone-Config; $c.Whitelist=@()
    foreach ($name in @('MC-Office','meituan')) { Check ((Get-Target (Snapshot (Link $name)) $c).Action -eq 'Disable') }
    Check ((Get-Target (Snapshot (Link 'Meituan-Guest')) $c).Action -eq 'Enable')
}
Case 'V31 SSID UTF-8 字节长度、中文、空格和 Ordinal 去重' {
    $c=Clone-Config; $c.Whitelist=@('中文网络',' Office ','xiaomi','XiaoMi')
    $v=ConvertFrom-ConfigurationText ($c | ConvertTo-Json)
    Check ($v.Whitelist.Count -eq 5 -and $v.Whitelist -contains ' Office ')
    foreach ($invalid in @('',('a'*33),('中'*11),"a`nb")) { $c.Whitelist=@($invalid); $rejected=$false; try { ConvertFrom-ConfigurationText ($c | ConvertTo-Json) | Out-Null } catch { $rejected=$true }; Check $rejected }
}
Case 'V31 配置热更新立即改变当前 XiaoMi 目标，不安装/重启任务' {
    $dir=Join-Path ([IO.Path]::GetTempPath()) ('WiFiV31-'+[Guid]::NewGuid().ToString('N'));[IO.Directory]::CreateDirectory($dir) | Out-Null
    $p=Join-Path $dir 'config.json'; $script:v31Log=[Collections.Generic.List[object]]::new()
    try {
        $c=Clone-Config; Write-JsonAtomic $p $c; $r=New-ConfigurationReloadState $p; $s=New-MonitorState
        Check ((Get-Target (Snapshot (Link 'XiaoMi')) $r.Config).Action -eq 'Enable')
        $services=New-Harness; $script:h.Network=Snapshot (Link 'XiaoMi'); $r.Config.Diagnostics='None'
        Cycle $s $services 0 $r.Config; Cycle $s $services 1 $r.Config; Check ($script:h.Actual.Enable)
        $c.Whitelist+=@('XiaoMi'); Write-JsonAtomic $p $c
        Check (Update-MonitorConfiguration $r $p $s {param($level,$message,$data) $script:v31Log.Add($level)})
        Check ((Get-Target (Snapshot (Link 'XiaoMi')) $r.Config).Action -eq 'Disable')
        $r.Config.Diagnostics='None'; Cycle $s $services 2 $r.Config; Cycle $s $services 3 $r.Config; Check (-not $script:h.Actual.Enable)
        Check ((Get-Target (Snapshot (Link 'Other' '192.168.1.1')) $r.Config).Server -eq '192.168.1.1:7890')
        $c.Whitelist=@('MC-Office','Meituan'); Write-JsonAtomic $p $c; Update-MonitorConfiguration $r $p $s {param($level,$message,$data)} | Out-Null
        Check ((Get-Target (Snapshot (Link 'XiaoMi')) $r.Config).Action -eq 'Enable')
        $r.Config.Diagnostics='None'; Cycle $s $services 4 $r.Config; Cycle $s $services 5 $r.Config; Check ($script:h.Actual.Enable -and $script:h.Actual.Server -eq '10.0.0.1:7890')
    } finally { Remove-TestFixture $dir }
}
Case 'V31 损坏配置保留最近有效值并记录错误，修复后可继续更新' {
    $dir=Join-Path ([IO.Path]::GetTempPath()) ('WiFiV31-'+[Guid]::NewGuid().ToString('N'));[IO.Directory]::CreateDirectory($dir) | Out-Null
    $p=Join-Path $dir 'config.json';$script:v31Errors=0
    try {
        $c=Clone-Config;$c.Whitelist+=@('XiaoMi');Write-JsonAtomic $p $c;$r=New-ConfigurationReloadState $p;$s=New-MonitorState;$revision=$r.Revision
        [IO.File]::WriteAllText($p,'{broken');Check (-not (Update-MonitorConfiguration $r $p $s {param($level,$message,$data)if($level -eq 'ERROR'){$script:v31Errors++}}))
        Check ($r.Revision -ceq $revision -and $r.Config.Whitelist -contains 'XiaoMi' -and $script:v31Errors -eq 1)
        for($i=0;$i -lt 10;$i++){Update-MonitorConfiguration $r $p $s {param($level,$message,$data)if($level -eq 'ERROR'){$script:v31Errors++}} | Out-Null};Check ($script:v31Errors -eq 1)
        $c.Port=9999;Write-JsonAtomic $p $c;Check (Update-MonitorConfiguration $r $p $s {param($level,$message,$data)});Check ($r.Config.Port -eq 9999)
    } finally {Remove-TestFixture $dir}
}
Case 'V31 多次快速修改最后一次有效配置生效并清除旧诊断/防抖' {
    $dir=Join-Path ([IO.Path]::GetTempPath()) ('WiFiV31-'+[Guid]::NewGuid().ToString('N'));[IO.Directory]::CreateDirectory($dir) | Out-Null
    $p=Join-Path $dir 'config.json'
    try { $c=Clone-Config;Write-JsonAtomic $p $c;$r=New-ConfigurationReloadState $p;$s=New-MonitorState;$s.Stability.Key='old';$s.Health.Health='Unavailable';$s.HealthKey='old'
        foreach($i in 1..30){$c.Whitelist=@('SSID-'+$i);Write-JsonAtomic $p $c};Check (Update-MonitorConfiguration $r $p $s {param($level,$message,$data)})
        Check ($r.Config.Whitelist -contains 'SSID-30' -and $s.Stability.Key -eq '' -and $s.Health.Health -eq 'Unknown')
    } finally {Remove-TestFixture $dir}
}
Case 'V31 保存中断遗留临时文件不影响有效配置，重新登录可从有效备份恢复' {
    $dir=Join-Path ([IO.Path]::GetTempPath()) ('WiFiV31-'+[Guid]::NewGuid().ToString('N'));[IO.Directory]::CreateDirectory($dir) | Out-Null
    $p=Join-Path $dir 'config.json'
    try { $c=Clone-Config;$c.Whitelist+=@('XiaoMi');Write-JsonAtomic $p $c;[IO.File]::WriteAllText($p+'.tmp.interrupted','{partial');Check ((New-ConfigurationReloadState $p).Config.Whitelist -contains 'XiaoMi')
        Copy-Item -LiteralPath $p -Destination ($p+'.previous');[IO.File]::WriteAllText($p,'{partial');$r=New-ConfigurationReloadState $p;Check ($r.Fallback -and $r.Config.Whitelist -contains 'XiaoMi')
    } finally {Remove-TestFixture $dir}
}
Case 'V31 暂停生产包装不读取/改写网络代理，退出 GUI 不参与监控' {
    $script:v31Heartbeat=$null
    $services=@{IsPaused={$true};Heartbeat={param($data)$script:v31Heartbeat=$data};ReadNetwork={throw '不应读取网络'};ReadProxy={throw '不应读取代理'};Apply={throw '不应写代理'}}
    $cycle=Invoke-AutomaticMonitorCycle (New-MonitorState) (Clone-Config) $services 1.0
    Check ($cycle.Paused -and $script:v31Heartbeat.Target -eq 'Paused' -and $script:v31Heartbeat.Reason.Contains('保持不变'))
}
Case 'V31 热更新等待可打断 300 秒轮询' {
    $clock=[Diagnostics.Stopwatch]::StartNew();Check (Wait-MonitorSignal 300000 $null {$false} {$true});Check ($clock.ElapsedMilliseconds -lt 1000)
}
Case 'V31 托盘登录入口更新/卸载及同名非归属命令保护（模拟注册表）' {
    $script:v31RunValue=''; $key=[pscustomobject]@{}
    $key | Add-Member ScriptMethod GetValue { param($name,$fallback) return $script:v31RunValue }
    $key | Add-Member ScriptMethod SetValue { param($name,$value,$kind) $script:v31RunValue=$value }
    $key | Add-Member ScriptMethod DeleteValue { param($name,$throw) $script:v31RunValue='' }
    $key | Add-Member ScriptMethod Dispose { }
    $script:v31RunKey=$key
    function Open-TrayLoginRegistry { return $script:v31RunKey }
    $m=[pscustomobject]@{Current='app/3.1.0-AAAAAAAAAAAA/WiFiProxySwitcher.exe';Files=@([pscustomobject]@{Path='app/3.0.0-BBBBBBBBBBBB/WiFiProxySwitcher.exe'},[pscustomobject]@{Path='app/3.1.0-AAAAAAAAAAAA/WiFiProxySwitcher.exe'})}
    $dir=Join-Path ([IO.Path]::GetTempPath()) 'WiFi Tray Mock'
    Set-TrayLoginEntry $dir $m $true;Check ($script:v31RunValue.EndsWith('" /tray') -and $script:v31RunValue.Contains('3.1.0'))
    Set-TrayLoginEntry $dir $m $false;Check ($script:v31RunValue -eq '')
    $script:v31RunValue='"C:\other.exe" /tray';$rejected=$false;try{Set-TrayLoginEntry $dir $m $false}catch{$rejected=$true};Check ($rejected -and $script:v31RunValue.Contains('other.exe'))
}
Case 'V31 升级保留自定义名单、登录偏好与原始代理备份（模拟安装）' {
    New-LifeFixture; . $lifeMocks
    try {
        $m=Install-ProductFiles $script:life.Source $script:life.Root $null
        $p=Join-Path $script:life.Root 'config.json';$c=Read-Configuration $p;$c.Whitelist+=@('XiaoMi');$c | Add-Member NoteProperty LoginMonitor $false -Force;Write-JsonAtomic $p $c
        $before=[IO.File]::ReadAllBytes((Join-Path $script:life.Root 'state/proxy-before-install.json'))
        Install-ProductFiles $script:life.Source $script:life.Root $m | Out-Null
        $saved=Read-Configuration $p;Check ($saved.Whitelist -contains 'XiaoMi' -and -not $saved.LoginMonitor)
        Check ([Convert]::ToBase64String($before) -ceq [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $script:life.Root 'state/proxy-before-install.json'))))
    } finally {Remove-TestFixture $script:life.Base}
}

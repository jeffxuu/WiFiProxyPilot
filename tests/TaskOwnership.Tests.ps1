# Loaded by Run-Tests.ps1. Windows account resolution and scheduling are explicit doubles.
function New-TaskQa([string]$Root=([IO.Path]::Combine([IO.Path]::GetTempPath(),'WiFiTaskQa'))) {
    $sid='S-1-5-21-100-200-300-1001'
    $manifest=[pscustomobject]@{OwnerSid=$sid;Root=$Root;TaskName=('WiFiProxySwitcher-'+$sid)}
    $task=[pscustomobject]@{
        TaskName=$manifest.TaskName;TaskPath='\';State='Ready'
        Description=('WiFiProxySwitcher-v1|'+$sid+'|'+$Root)
        Principal=[pscustomobject]@{UserId=$sid;GroupId='';LogonType='Interactive';RunLevel='Limited'}
        Actions=@([pscustomobject]@{Execute='C:\Windows\System32\wscript.exe';Arguments='//B //Nologo ".\SilentLauncher.vbs" Watch';WorkingDirectory=$Root})
    }
    $accounts=@{}; foreach ($name in @($sid,'XU','TEST-PC\XU','.\XU','DOMAIN\XU','AzureAD\user@example.test','MicrosoftAccount\user@example.test','TEST-PC\中文用户')) { $accounts[$name]=$sid }
    $script:tq=@{Sid=$sid;Manifest=$manifest;Task=$task;Tasks=@($task);Accounts=$accounts;Resolutions=0;Running=$false;Held=$false;Starts=0;Enabled=0;Disabled=0;Stops=0}
}
$taskQaMocks={
    function Resolve-TaskUserSid([string]$UserId) {
        $script:tq.Resolutions++
        if (-not $script:tq.Accounts.ContainsKey($UserId)) { throw '模拟 Windows 账户 SID 解析失败' }
        return $script:tq.Accounts[$UserId]
    }
    function Get-WscriptPath { 'C:\Windows\System32\wscript.exe' }
    function Get-ScheduledTask { param($ErrorAction) $script:tq.Tasks }
}
$taskQaSchedulerMocks={
    function New-UserMutex($Purpose) {
        $m=[pscustomobject]@{}
        $m | Add-Member ScriptMethod WaitOne { param($timeout) if ($script:tq.Running -or $script:tq.Held) { return $false }; $script:tq.Held=$true; return $true }
        $m | Add-Member ScriptMethod ReleaseMutex { $script:tq.Held=$false }
        $m | Add-Member ScriptMethod Dispose {}
        return $m
    }
    function Enable-ScheduledTask { param($TaskName,$TaskPath,$ErrorAction) $script:tq.Enabled++ }
    function Disable-ScheduledTask { param($TaskName,$TaskPath,$ErrorAction) $script:tq.Disabled++ }
    function Stop-ScheduledTask { param($TaskName,$TaskPath,$ErrorAction) $script:tq.Stops++; $script:tq.Running=$false; $script:tq.Task.State='Ready' }
    function Start-ScheduledTask {
        param($TaskName,$TaskPath,$ErrorAction)
        Check (-not $script:tq.Held)
        $script:tq.Starts++; $script:tq.Running=$true; $script:tq.Task.State='Running'
        Write-JsonAtomic (Join-Path $script:tq.Manifest.Root 'state/status.json') @{Time=[DateTimeOffset]::Now.ToString('o');RunId='principal-hotfix';Outcome='Enable'}
    }
    function Start-Sleep { param($Milliseconds) }
}
function Assert-TaskQaRejected([string]$Reason) {
    $message=''
    try { Assert-OwnedTaskDefinition $script:tq.Task $script:tq.Manifest } catch { $message=$_.Exception.Message }
    Check ($message.Contains($Reason)) ('拒绝结果未包含预期原因 ['+$Reason+']: '+$message)
}

Case 'TaskFix 同账户 SID/短名/域名/中文/云账户别名均按已解析 SID 验证' {
    New-TaskQa; . $taskQaMocks
    foreach ($name in $script:tq.Accounts.Keys) { $script:tq.Task.Principal.UserId=$name; Assert-OwnedTaskDefinition $script:tq.Task $script:tq.Manifest }
    Check ($script:tq.Resolutions -eq $script:tq.Accounts.Count) '每个账户形式必须经过 SID 解析边界'
}
Case 'TaskFix CIM uint32/uint16/数字字符串和实际 CLR 枚举均接受 Interactive=3 Limited=0' {
    New-TaskQa; . $taskQaMocks
    if (-not ('WiFiTaskLogonQa' -as [type])) { Add-Type 'public enum WiFiTaskLogonQa { Interactive = 3, Password = 1 } public enum WiFiTaskLevelQa { Limited = 0, Highest = 1 }' }
    foreach ($pair in @(@([uint32]3,[uint32]0),@([uint16]3,[uint16]0),@('3','0'),@('interactive','limited'),@([WiFiTaskLogonQa]::Interactive,[WiFiTaskLevelQa]::Limited))) {
        $script:tq.Task.Principal.LogonType=$pair[0]; $script:tq.Task.Principal.RunLevel=$pair[1]
        Assert-OwnedTaskDefinition $script:tq.Task $script:tq.Manifest
    }
}
Case 'TaskFix Password/S4U/Group/服务登录/Highest/缺失字段仍拒绝' {
    New-TaskQa; . $taskQaMocks
    foreach ($value in @($null,'',0,1,2,4,5,6,-1,99,$true,3.5,'Password','S4U','Group','ServiceAccount','InteractiveOrPassword','InteractiveToken')) {
        $script:tq.Task.Principal.LogonType=$value; Assert-TaskQaRejected '登录方式'
    }
    $script:tq.Task.Principal.LogonType=3
    foreach ($value in @($null,'',1,-1,99,$false,0.5,'Highest','HighestAvailable','LeastPrivilege')) {
        $script:tq.Task.Principal.RunLevel=$value; Assert-TaskQaRejected '运行级别'
    }
}
Case 'TaskFix 不同 SID/不可解析账户/空账户/组主体均拒绝' {
    New-TaskQa; . $taskQaMocks
    $script:tq.Accounts['OTHER-PC\XU']='S-1-5-21-100-200-999-1001'
    $script:tq.Task.Principal.UserId='OTHER-PC\XU'; Assert-TaskQaRejected 'SID 不匹配'
    $script:tq.Task.Principal.UserId='unknown'; Assert-TaskQaRejected '解析失败'
    $script:tq.Task.Principal.UserId=''; Assert-TaskQaRejected '解析失败'
    $script:tq.Task.Principal.UserId=$script:tq.Sid; $script:tq.Task.Principal.GroupId='S-1-5-32-544'; Assert-TaskQaRejected '用户组'
}
Case 'TaskFix 当前显示名称相同但 SID 不同不能绕过所有权验证' {
    New-TaskQa; . $taskQaMocks
    function Get-UserName { 'XU' }
    $script:tq.Accounts['XU']='S-1-5-21-999-999-999-1001'
    $script:tq.Task.Principal.UserId='XU'; Assert-TaskQaRejected 'SID 不匹配'
}
Case 'TaskFix 账户兼容不会放宽描述/目录/脚本/动作数量验证' {
    New-TaskQa; . $taskQaMocks
    $script:tq.Task.Principal.UserId='XU'; $script:tq.Task.Principal.LogonType=3; $script:tq.Task.Principal.RunLevel=0
    $script:tq.Task.Description='another product'; Assert-TaskQaRejected '任务描述'
    $script:tq.Task.Description='WiFiProxySwitcher-v1|'+$script:tq.Sid+'|'+$script:tq.Manifest.Root
    $script:tq.Task.Actions[0].WorkingDirectory='C:\Other'; Assert-TaskQaRejected '动作'
    $script:tq.Task.Actions[0].WorkingDirectory=$script:tq.Manifest.Root; $script:tq.Task.Actions[0].Arguments='another-script.vbs'; Assert-TaskQaRejected '动作'
    $script:tq.Task.Actions[0].Arguments='//B //Nologo ".\SilentLauncher.vbs" Watch'; $script:tq.Task.Actions += $script:tq.Task.Actions[0]; Assert-TaskQaRejected '动作'
}
Case 'TaskFix 拒绝时仍能只读采集 UserId/SID/原始枚举类型及具体失败原因' {
    New-TaskQa; . $taskQaMocks
    $script:tq.Task.Principal.UserId='unknown'; $script:tq.Task.Principal.LogonType=[uint32]3; $script:tq.Task.Principal.RunLevel=[uint32]1
    $d=Get-TaskOwnershipDetails $script:tq.Task $script:tq.Manifest
    Check ($d.UserId -ceq 'unknown' -and $d.LogonType -ceq '3' -and $d.LogonTypeClrType -ceq 'System.UInt32' -and $d.AccountResolutionError)
    Assert-TaskQaRejected 'UserId'
    Assert-TaskQaRejected '运行级别'
    $script:tq.Task.Principal=$null; Assert-TaskQaRejected '登录方式'
}
Case 'TaskFix 实际任务查询只接受根目录目标任务，零项返回空，多项拒绝' {
    New-TaskQa; . $taskQaMocks
    $script:tq.Task.Principal.UserId='XU'; $script:tq.Task.Principal.LogonType=[uint32]3; $script:tq.Task.Principal.RunLevel=[uint32]0
    $script:tq.Tasks += [pscustomobject]@{TaskName=$script:tq.Manifest.TaskName;TaskPath='\Other\'}
    Check ([object]::ReferenceEquals((Get-OwnedTask $script:tq.Manifest),$script:tq.Task))
    $script:tq.Tasks=@(); Check ($null -eq (Get-OwnedTask $script:tq.Manifest))
    $script:tq.Tasks=@($script:tq.Task,$script:tq.Task); $caught=$false
    try { Get-OwnedTask $script:tq.Manifest | Out-Null } catch { $caught=$_.Exception.Message.Contains('不唯一') }; Check $caught
}
Case 'TaskFix 生产 Start/Stop 调用链使用真实归属校验接受短名和 CIM 数值' {
    $temp=Join-Path ([IO.Path]::GetTempPath()) ('WiFi TaskFix '+[Guid]::NewGuid().ToString('N'))
    New-TaskQa $temp; . $taskQaMocks; . $taskQaSchedulerMocks
    [IO.Directory]::CreateDirectory((Join-Path $temp 'state')) | Out-Null
    $script:tq.Task.Principal.UserId='XU'; $script:tq.Task.Principal.LogonType=[uint32]3; $script:tq.Task.Principal.RunLevel=[uint32]0
    try {
        Start-OwnedWatcher $script:tq.Manifest | Out-Null
        Check ($script:tq.Starts -eq 1 -and $script:tq.Enabled -eq 1 -and $script:tq.Running)
        Stop-OwnedWatcher $script:tq.Manifest
        Check ($script:tq.Disabled -eq 1 -and $script:tq.Stops -eq 1 -and -not $script:tq.Running)
        Check (Test-Path -LiteralPath (Join-Path $temp 'state/stop.request'))
    } finally { Remove-Item -LiteralPath $temp -Recurse -Force }
}
Case 'TaskFix 失败安装后从完整新包重装通过实际归属检查且原备份/config 不变' {
    New-LifeFixture; New-TaskQa $script:life.Root; . $taskQaMocks; . $taskQaSchedulerMocks
    function Get-UserSid { $script:tq.Sid }
    function Assert-ProxyPolicy {}
    function Protect-InstallDirectory([string]$Root) {}
    function Get-ManualSnapshot { Registry-Snapshot $false 'original:80' 'original.local' }
    try {
        $script:tq.Tasks=@()
        $m=Install-ProductFiles $script:life.Source $script:life.Root $null
        $before=[IO.File]::ReadAllBytes((Join-Path $script:life.Root 'state/proxy-before-install.json'))
        $c=Clone-Config; $c.Mode='Safe'; Write-JsonAtomic (Join-Path $script:life.Root 'config.json') $c
        $script:tq.Task.Principal.UserId='XU'; $script:tq.Task.Principal.LogonType=[uint32]3; $script:tq.Task.Principal.RunLevel=[uint32]0
        $script:tq.Tasks=@($script:tq.Task)
        $updated=Install-ProductFiles $script:life.Source $script:life.Root $m
        Check ($script:tq.Disabled -eq 1 -and $script:tq.Resolutions -gt 0)
        Check (([Convert]::ToBase64String($before)) -ceq [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $script:life.Root 'state/proxy-before-install.json'))))
        Check ((Read-Configuration (Join-Path $script:life.Root 'config.json')).Mode -eq 'Safe')
        Check ($updated.OwnerSid -ceq $script:tq.Sid)
    } finally { Remove-Item -LiteralPath $script:life.Base -Recurse -Force }
}

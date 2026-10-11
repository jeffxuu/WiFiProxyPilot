Set-StrictMode -Version 2.0
$script:Pointer='Software\WiFiProxySwitcher'
$script:TaskPrefix='WiFiProxySwitcher-'

function Get-ProductFiles {
    return @('Control.ps1','ProxyWatcher.ps1','Diagnose.ps1','SilentLauncher.vbs','config.json','README.md','Install.bat','Start.bat','Stop.bat','Uninstall.bat','RestoreProxy.bat','Status.bat','Diagnose.bat','lib/Core.ps1','lib/Windows.ps1','lib/Native.cs','lib/Monitor.ps1','lib/Lifecycle.ps1','tests/Run-Tests.ps1','tests/Run-Tests.bat','tests/ProbeServer.cs','tests/Round2.Tests.ps1','tests/TaskOwnership.Tests.ps1','docs/ARCHITECTURE.md','docs/WINDOWS_ACCEPTANCE.md','docs/TEST_RESULTS.md','docs/REVIEW_ROUND2.md','docs/TASK_OWNERSHIP_FIX.md','docs/test-results.json')
}
function Assert-InstallManifest($Manifest) {
    $allowed=Get-ProductFiles; $seen=@{}
    foreach ($entry in $Manifest.Files) {
        $name=$entry.Path.Replace('\','/')
        if ($name -cnotin $allowed -or $seen.ContainsKey($name) -or $entry.Hash -notmatch '^[0-9a-fA-F]{64}$') { throw '安装清单存在未知/重复路径或无效哈希，拒绝操作' }
        $seen[$name]=$true
        Assert-PlainPath (Join-Path $Manifest.Root $name)
    }
    foreach ($required in @('Control.ps1','ProxyWatcher.ps1','SilentLauncher.vbs','config.json')) { if (-not $seen.ContainsKey($required)) { throw '安装清单缺少必要文件' } }
}
function Get-UserName { return [Security.Principal.WindowsIdentity]::GetCurrent().Name }
function Get-WscriptPath { return Join-Path $env:SystemRoot 'System32/wscript.exe' }
function Get-TaskField($Object,[string]$Name) {
    if ($null -eq $Object) { return $null }
    $p=$Object.PSObject.Properties[$Name]
    if ($null -ne $p) { return $p.Value }
    return $null
}
function Resolve-TaskUserSid([string]$UserId) {
    if ([string]::IsNullOrWhiteSpace($UserId)) { throw '任务没有 UserId，不能确认账户归属' }
    try {
        if ($UserId.StartsWith('S-',[StringComparison]::OrdinalIgnoreCase)) { return [Security.Principal.SecurityIdentifier]::new($UserId).Value }
        # Task Scheduler may return a local short name, DOMAIN\name, or another account alias.
        # Resolve with Windows; comparing display names or dropping the domain is unsafe.
        return [Security.Principal.NTAccount]::new($UserId).Translate([Security.Principal.SecurityIdentifier]).Value
    } catch { throw ('无法将任务账户解析为 SID；UserId=['+$UserId+']；'+$_.Exception.Message) }
}
function Test-TaskPrincipalValue($Value,[string]$Name,[int]$Number) {
    if ($null -eq $Value) { return $false }
    # MSFT_TaskPrincipal: Interactive=3, Limited=0. CIM readback can be numeric;
    # ScheduledTasks type adapters may instead return the corresponding enum names.
    if ($Value.GetType().IsEnum) { return [Convert]::ToInt64($Value) -eq $Number }
    $text=[string]$Value
    return [string]::Equals($text,$Name,[StringComparison]::OrdinalIgnoreCase) -or [string]::Equals($text,$Number.ToString([Globalization.CultureInfo]::InvariantCulture),[StringComparison]::Ordinal)
}
function Get-TaskOwnershipDetails($Task,$Manifest) {
    $principal=Get-TaskField $Task 'Principal'
    $logon=Get-TaskField $principal 'LogonType'; $level=Get-TaskField $principal 'RunLevel'
    $logonType='null'; $levelType='null'
    if ($null -ne $logon) { $logonType=$logon.GetType().FullName }
    if ($null -ne $level) { $levelType=$level.GetType().FullName }
    $userId=[string](Get-TaskField $principal 'UserId'); $resolvedSid=$null; $resolutionError=$null
    try { $resolvedSid=Resolve-TaskUserSid $userId } catch { $resolutionError=$_.Exception.Message }
    return [pscustomobject]@{
        TaskName=$Manifest.TaskName; ExpectedOwnerSid=$Manifest.OwnerSid
        UserId=$userId; ResolvedOwnerSid=$resolvedSid; AccountResolutionError=$resolutionError
        GroupId=[string](Get-TaskField $principal 'GroupId')
        LogonType=[string]$logon; LogonTypeClrType=$logonType
        RunLevel=[string]$level; RunLevelClrType=$levelType
        DescriptionMatches=([string](Get-TaskField $Task 'Description') -ceq ('WiFiProxySwitcher-v1|'+$Manifest.OwnerSid+'|'+$Manifest.Root))
    }
}
function Assert-OwnedTaskDefinition($Task,$Manifest) {
    $details=Get-TaskOwnershipDetails $Task $Manifest
    $principal=Get-TaskField $Task 'Principal'
    $issues=[Collections.Generic.List[string]]::new()
    if (-not $details.DescriptionMatches) { $issues.Add('任务描述/安装目录不匹配') }
    if ($details.AccountResolutionError) { $issues.Add($details.AccountResolutionError) }
    elseif (-not [string]::Equals($details.ResolvedOwnerSid,$Manifest.OwnerSid,[StringComparison]::OrdinalIgnoreCase)) { $issues.Add('运行账户 SID 不匹配') }
    if ($details.GroupId) { $issues.Add('不允许使用用户组作为运行主体') }
    if (-not (Test-TaskPrincipalValue (Get-TaskField $principal 'LogonType') 'Interactive' 3)) { $issues.Add('登录方式必须是 Interactive (3)') }
    if (-not (Test-TaskPrincipalValue (Get-TaskField $principal 'RunLevel') 'Limited' 0)) { $issues.Add('运行级别必须是 Limited (0)') }
    if ($issues.Count) { throw ('同名任务的所有者/权限不匹配，拒绝修改：'+($issues -join '；')+'；任务字段='+($details | ConvertTo-Json -Compress)) }
    $actions=@($Task.Actions)
    $exe=Get-WscriptPath
    $legacy='//B //Nologo "'+(Join-Path $Manifest.Root 'SilentLauncher.vbs')+'" Watch'
    if ($actions.Count -ne 1 -or -not [string]::Equals($actions[0].Execute,$exe,[StringComparison]::OrdinalIgnoreCase) -or $actions[0].Arguments -cnotin @($legacy,'//B //Nologo ".\SilentLauncher.vbs" Watch') -or -not [string]::Equals($actions[0].WorkingDirectory,$Manifest.Root,[StringComparison]::OrdinalIgnoreCase)) { throw '同名任务动作已被修改，拒绝启动或终止不明程序' }
}
function Remove-InstallPointer([string]$Root) {
    if (-not [string]::Equals((Get-InstalledRoot),$Root,[StringComparison]::OrdinalIgnoreCase)) { throw '安装指针发生变化，拒绝移除其他安装的记录' }
    $key=[Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($script:Pointer,$true)
    $empty=$false
    try { $key.DeleteValue('InstallDir',$false); $empty=($key.GetValueNames().Length -eq 0 -and $key.GetSubKeyNames().Length -eq 0) } finally { $key.Dispose() }
    if ($empty) { [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKey($script:Pointer,$false) }
}
function Write-ControlFailure([string]$Action,[string]$Message) {
    try {
        $dir=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'WiFiProxySwitcher-Control'
        [IO.Directory]::CreateDirectory($dir) | Out-Null; $path=Join-Path $dir 'control-errors.log'
        if ((Test-Path -LiteralPath $path) -and (Get-Item -LiteralPath $path).Length -gt 262144) { Move-Item -LiteralPath $path -Destination ($path+'.1') -Force }
        [IO.File]::AppendAllText($path,([DateTimeOffset]::Now.ToString('o')+' '+$Action+' '+$Message+[Environment]::NewLine),[Text.UTF8Encoding]::new($true))
    } catch { Write-Error ('错误日志写入失败: '+$_.Exception.Message+'；原错误: '+$Message) -ErrorAction Continue }
}

function Copy-ProductPayload([string]$Source,[string]$Root,[switch]$PreserveConfig) {
    foreach ($name in Get-ProductFiles) {
        if ($PreserveConfig -and $name -eq 'config.json') { continue }
        $src=Join-Path $Source $name; $dst=Join-Path $Root $name
        Assert-PlainPath $dst
        if (-not [string]::Equals([IO.Path]::GetFullPath($src),[IO.Path]::GetFullPath($dst),[StringComparison]::OrdinalIgnoreCase)) {
            [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($dst)) | Out-Null
            Copy-Item -LiteralPath $src -Destination $dst -Force
        }
    }
}
function New-InstallManifest([string]$Root,[string]$FilesRoot,$Previous,[switch]$InPlace) {
    $manifest=[pscustomobject]@{Product='WiFiProxySwitcher-v1';Root=$Root;OwnerSid=(Get-UserSid);TaskName=($script:TaskPrefix+(Get-UserSid));Files=@()}
    foreach ($name in Get-ProductFiles) {
        $hash=(Get-FileHash -LiteralPath (Join-Path $FilesRoot $name) -Algorithm SHA256).Hash
        if ($null -ne $Previous -and ($name -eq 'config.json' -or $InPlace)) {
            $old=@($Previous.Files | Where-Object { $_.Path.Replace('\','/') -ceq $name })
            if ($old.Count -eq 1) { $hash=$old[0].Hash }
        }
        $manifest.Files += [pscustomobject]@{Path=$name;Hash=$hash}
    }
    return $manifest
}
function Install-ProductFiles([string]$Source,[string]$Root,$Previous) {
    if ($null -ne $Previous -and $null -ne $Previous.PSObject.Properties['Phase'] -and $Previous.Phase -eq 'Uninstalling') { throw '上次卸载尚未完成，请先从完整项目包运行 Uninstall.bat -InstallDir 指定此目录' }
    # Complete source and config preflight happens before stopping an existing monitor or touching its files.
    foreach ($name in Get-ProductFiles) {
        $p=Join-Path $Source $name
        if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { throw ('安装包文件缺失: '+$name) }
        Assert-PlainPath $p
    }
    $configPath=Join-Path $Source 'config.json'; if ($null -ne $Previous) { $configPath=Join-Path $Root 'config.json' }
    Read-Configuration $configPath | Out-Null
    foreach ($name in Get-ProductFiles) { Assert-PlainPath (Join-Path $Root $name) }
    if ($null -ne $Previous) {
        Read-OriginalProxy $Root | Out-Null
        foreach ($name in Get-ProductFiles) {
            if ((Test-Path -LiteralPath (Join-Path $Root $name)) -and -not @($Previous.Files | Where-Object { $_.Path.Replace('\','/') -ceq $name }).Count) { throw ('新版本路径被非本工具文件占用，拒绝覆盖: '+$name) }
        }
    }
    $prospective=[pscustomobject]@{Root=$Root;OwnerSid=(Get-UserSid);TaskName=($script:TaskPrefix+(Get-UserSid))}
    Get-OwnedTask $prospective | Out-Null
    Assert-ProxyPolicy
    if ($null -ne $Previous) {
        if (-not (Test-Path -LiteralPath (Join-Path $Root 'state/proxy-before-install.json'))) { throw '原配置备份丢失，拒绝更新安装' }
        Stop-OwnedWatcher $Previous
        if (-not [string]::Equals($Source,$Root,[StringComparison]::OrdinalIgnoreCase)) {
            $backupDir=Join-Path $Root ('user-backups/'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+[Guid]::NewGuid().ToString('N'))
            foreach ($entry in $Previous.Files) {
                $name=$entry.Path.Replace('\','/'); $p=Join-Path $Root $name
                if ($name -ne 'config.json' -and (Test-Path -LiteralPath $p) -and (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash -cne $entry.Hash) {
                    $dest=Join-Path $backupDir $name; Assert-PlainPath $dest
                    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($dest)) | Out-Null
                    Copy-Item -LiteralPath $p -Destination $dest -Force
                }
            }
        }
        Copy-ProductPayload $Source $Root -PreserveConfig
        $manifest=New-InstallManifest $Root $Root $Previous -InPlace:([string]::Equals($Source,$Root,[StringComparison]::OrdinalIgnoreCase))
        Write-JsonAtomic (Join-Path $Root 'state/installation.json') $manifest
        return $manifest
    }
    # Stage the complete first installation beside the target; a copy failure cannot strand a half-install there.
    $stage=$Root+'.stage.'+[Guid]::NewGuid().ToString('N')
    try {
        [IO.Directory]::CreateDirectory($stage) | Out-Null; Protect-InstallDirectory $stage
        Copy-ProductPayload $Source $stage
        [IO.Directory]::CreateDirectory((Join-Path $stage 'state')) | Out-Null
        $before=Get-ManualSnapshot
        Assert-ManualSnapshot $before
        Write-JsonAtomic (Join-Path $stage 'state/proxy-before-install.json') $before
        Write-JsonAtomic (Join-Path $stage 'state/last-applied.json') $before
        [IO.File]::WriteAllText((Join-Path $stage 'state/stop.request'),'installing')
        $manifest=New-InstallManifest $Root $stage $null
        Write-JsonAtomic (Join-Path $stage 'state/installation.json') $manifest
        if (Test-Path -LiteralPath $Root) {
            if (@(Get-ChildItem -LiteralPath $Root -Force).Count) { throw '目标目录已产生文件，拒绝替换' }
            [IO.Directory]::Delete($Root)
        }
        [IO.Directory]::Move($stage,$Root)
        return $manifest
    } finally { if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force } }
}

function Uninstall-Product($Manifest,[switch]$KeepCurrentProxy,[switch]$DeleteLogs,[switch]$ForceRestore) {
    Assert-InstallManifest $Manifest
    Stop-OwnedWatcher $Manifest
    $finalizing=$null -ne $Manifest.PSObject.Properties['Phase'] -and $Manifest.Phase -eq 'Uninstalling'
    if (-not $finalizing) {
        if (-not $KeepCurrentProxy) { Restore-OwnedProxy $Manifest -Force:$ForceRestore } else { Write-Output '根据明确选项保留当前代理配置' }
        $Manifest | Add-Member NoteProperty Phase 'Uninstalling' -Force
        Write-JsonAtomic (Join-Path $Manifest.Root 'state/installation.json') $Manifest
    }
    $task=Get-OwnedTask $Manifest
    if ($null -ne $task) { Unregister-ScheduledTask -TaskName $Manifest.TaskName -TaskPath '\' -Confirm:$false -ErrorAction Stop }
    # Keep the durable marker and original backup until all fallible product-file deletion has succeeded.
    foreach ($entry in @($Manifest.Files | Sort-Object @{Expression={if ($_.Path -eq 'Control.ps1') {1} else {0}}})) {
        $p=Join-Path $Manifest.Root $entry.Path.Replace('\','/')
        Assert-PlainPath $p
        if (Test-Path -LiteralPath $p) {
            if ((Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash -ceq $entry.Hash) { Remove-Item -LiteralPath $p -Force }
            else { Write-Output ('文件被用户修改，保留: '+$entry.Path) }
        }
    }
    $logDir=Join-Path $Manifest.Root 'logs'
    if ($DeleteLogs -and (Test-Path -LiteralPath $logDir)) {
        Get-ChildItem -LiteralPath $logDir -File -ErrorAction Stop | Where-Object { $_.Name -match '^watcher\.jsonl(\.[0-9]+)?$' } | Remove-Item -Force -ErrorAction Stop
    }
    # Remove only our pointer value; leave unrelated values/subkeys untouched. A surviving marker supports -InstallDir recovery.
    if (Get-InstalledRoot) { Remove-InstallPointer $Manifest.Root }
    foreach ($name in @('last-applied.json','proxy-before-install.json','status.json','control-status.json','stop.request','installation.json')) {
        $p=Join-Path $Manifest.Root ('state/'+$name); Assert-PlainPath $p
        if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force }
    }
    # Empty installation directories are harmless and deliberately retained; never recursively erase a user's root.
    Write-Output '卸载完成：专属任务和启动指针已移除。保留空目录、所选日志及用户改动的文件'
}

function Get-InstalledRoot {
    $k=[Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($script:Pointer)
    try { if ($null -ne $k) { return [string]$k.GetValue('InstallDir','') }; return '' } finally { if ($null -ne $k) { $k.Dispose() } }
}
function Read-Install([string]$Root) {
    Assert-PlainPath $Root
    foreach ($sub in @('state','lib','logs','state\installation.json','state\proxy-before-install.json','state\last-applied.json')) { Assert-PlainPath (Join-Path $Root $sub) }
    $file=Join-Path $Root 'state\installation.json'
    if (-not (Test-Path -LiteralPath $file)) { throw '没有有效安装记录，请先运行 Install.bat' }
    $m=Get-Content -LiteralPath $file -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($m.Product -cne 'WiFiProxySwitcher-v1' -or $m.OwnerSid -cne (Get-UserSid) -or -not [string]::Equals([IO.Path]::GetFullPath($m.Root),[IO.Path]::GetFullPath($Root),[StringComparison]::OrdinalIgnoreCase)) { throw '安装记录不属于本工具/当前用户/此目录，拒绝操作' }
    if ($m.TaskName -cne ($script:TaskPrefix+(Get-UserSid))) { throw '任务名称记录无效' }
    Assert-InstallManifest $m
    return $m
}
function Get-ProductTask($Manifest) {
    # Read-only candidate lookup. Callers that mutate/start/stop MUST use Get-OwnedTask.
    $tasks=@(Get-ScheduledTask -ErrorAction Stop | Where-Object { $_.TaskPath -eq '\' -and $_.TaskName -ceq $Manifest.TaskName })
    if ($tasks.Count -eq 0) { return $null }
    if ($tasks.Count -ne 1) { throw '同名任务查询结果不唯一，拒绝操作' }
    return $tasks[0]
}
function Get-OwnedTask($Manifest) {
    $t=Get-ProductTask $Manifest
    if ($null -eq $t) { return $null }
    Assert-OwnedTaskDefinition $t $Manifest
    return $t
}
function Stop-OwnedWatcher($Manifest) {
    [IO.File]::WriteAllText((Join-Path $Manifest.Root 'state\stop.request'),'stop',[Text.UTF8Encoding]::new($true))
    $task=Get-OwnedTask $Manifest
    if ($null -ne $task) { Disable-ScheduledTask -TaskName $Manifest.TaskName -TaskPath '\' -ErrorAction Stop | Out-Null }
    $watch=New-UserMutex 'Watcher'; $taken=$false
    try {
        $taken=Enter-Mutex $watch 15000
        if (-not $taken -and $null -ne $task) {
            $latest=Get-OwnedTask $Manifest
            if ($null -ne $latest -and $latest.State -in @('Running','Queued')) { Stop-ScheduledTask -TaskName $Manifest.TaskName -TaskPath '\' -ErrorAction Stop }
            $taken=Enter-Mutex $watch 10000
        }
        if (-not $taken) { throw '监控仍持有锁，拒绝恢复或卸载；请查看任务计划程序后重试' }
        # A task launcher may be starting before the watcher takes its mutex. Stop the owned task as well.
        if ($null -ne $task) {
            $latest=Get-OwnedTask $Manifest
            if ($null -ne $latest -and $latest.State -in @('Running','Queued')) { Stop-ScheduledTask -TaskName $Manifest.TaskName -TaskPath '\' -ErrorAction Stop }
        }
    } finally { if ($taken) { $watch.ReleaseMutex() }; $watch.Dispose() }
}
function Start-OwnedWatcher($Manifest) {
    if ($null -ne $Manifest.PSObject.Properties['Phase'] -and $Manifest.Phase -eq 'Uninstalling') { throw '卸载尚未完成，拒绝重新启动监控' }
    $task=Get-OwnedTask $Manifest
    if ($null -eq $task) { throw '自启动任务缺失，请重复安装以修复' }
    $stop=Join-Path $Manifest.Root 'state/stop.request'
    if (Test-Path -LiteralPath $stop) { Stop-OwnedWatcher $Manifest }
    $watch=New-UserMutex 'Watcher'; $taken=$false
    try { $taken=Enter-Mutex $watch } finally { if ($taken) { $watch.ReleaseMutex() }; $watch.Dispose() }
    # Never hold the watcher mutex while scheduling: the child would exit as a duplicate.
    if (Test-Path -LiteralPath $stop) { Remove-Item -LiteralPath $stop -Force }
    Enable-ScheduledTask -TaskName $Manifest.TaskName -TaskPath '\' -ErrorAction Stop | Out-Null
    if (-not $taken) { Write-Output '已有监控实例运行，已确保登录自启启用'; return }
    $requested=[DateTimeOffset]::Now
    $statusPath=Join-Path $Manifest.Root 'state/status.json'
    if (Test-Path -LiteralPath $statusPath) { Remove-Item -LiteralPath $statusPath -Force }
    Start-ScheduledTask -TaskName $Manifest.TaskName -TaskPath '\' -ErrorAction Stop
    $ready=$false
    for ($i=0;$i -lt 30;$i++) {
        Start-Sleep -Milliseconds 500
        $w=New-UserMutex 'Watcher'; $free=Enter-Mutex $w
        if ($free) { $w.ReleaseMutex() }; $w.Dispose()
        if (-not $free -and (Test-Path -LiteralPath $statusPath)) {
            $s=Get-Content -LiteralPath $statusPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($s.Outcome -notin @('Starting','Stopped') -and (ConvertTo-RecordTime $s.Time) -ge $requested -and $s.RunId) { $ready=$true; break }
        }
    }
    if (-not $ready) { throw '任务已请求启动，但未收到本次启动的监控心跳。检查日志、执行策略、WSH 和任务历史' }
    Write-Output '监控已静默启动并收到新心跳；网络/代理结果请用 Status.bat 与日志确认'
}

function Restore-OwnedProxy($Manifest,[switch]$Force) {
    $original=Read-OriginalProxy $Manifest.Root
    $current=Get-ManualSnapshot
    if (Test-RestoreAllowed $current $original) { Restore-ManualSnapshot $original; Write-Output '当前注册表等于原配置，已重新通知并验证 WinINet'; return }
    $last=$null; $lastPath=Join-Path $Manifest.Root 'state\last-applied.json'
    if (Test-Path -LiteralPath $lastPath) { $last=Get-Content -LiteralPath $lastPath -Raw -Encoding UTF8 | ConvertFrom-Json }
    if (-not (Test-RestoreAllowed $current $last -Force:$Force)) { throw '检测到工具最后一次写入之后的代理变更或未完成写入。已停止监控；为保护后续修改，未恢复/删除安装。确认后使用 -ForceRestore；卸载也可用 -KeepCurrentProxy 保留当前配置' }
    Restore-ManualSnapshot $original
    Write-Output '已恢复安装前手动代理配置；PAC/自动检测保持当前设置'
}
function Read-OriginalProxy([string]$Root) {
    $path=Join-Path $Root 'state/proxy-before-install.json'; Assert-PlainPath $path
    $snapshot=Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-ManualSnapshot $snapshot
    return $snapshot
}
function Protect-InstallDirectory([string]$Root) {
    # Dedicated product directory: remove inherited write access, preserving user/SYSTEM/admin access.
    $acl=[Security.AccessControl.DirectorySecurity]::new()
    $acl.SetAccessRuleProtection($true,$false)
    $owner=[Security.Principal.SecurityIdentifier]::new((Get-UserSid)); $acl.SetOwner($owner)
    foreach ($sid in @($owner,[Security.Principal.SecurityIdentifier]::new('S-1-5-18'),[Security.Principal.SecurityIdentifier]::new('S-1-5-32-544'))) {
        $rule=[Security.AccessControl.FileSystemAccessRule]::new($sid,[Security.AccessControl.FileSystemRights]::FullControl,([Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [Security.AccessControl.InheritanceFlags]::ObjectInherit),[Security.AccessControl.PropagationFlags]::None,[Security.AccessControl.AccessControlType]::Allow)
        $acl.AddAccessRule($rule)
    }
    Set-Acl -LiteralPath $Root -AclObject $acl -ErrorAction Stop
}

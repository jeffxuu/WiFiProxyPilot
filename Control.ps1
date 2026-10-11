#requires -Version 5.1
[CmdletBinding()]
param(
    [ValidateSet('Install','Start','Stop','Uninstall','Restore','Status')][string]$Action='Status',
    [string]$InstallDir='',
    [switch]$ForceRestore,
    [switch]$KeepCurrentProxy,
    [switch]$DeleteLogs,
    [switch]$Quiet
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'lib\Core.ps1')
. (Join-Path $PSScriptRoot 'lib\Windows.ps1')
$script:Pointer='Software\WiFiProxySwitcher'
$script:TaskPrefix='WiFiProxySwitcher-'
$mutex=$null; $owned=$false; $code=0

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
    return $m
}
function Get-OwnedTask($Manifest) {
    $tasks=@(Get-ScheduledTask -ErrorAction Stop | Where-Object { $_.TaskPath -eq '\' -and $_.TaskName -ceq $Manifest.TaskName })
    if ($tasks.Count -eq 0) { return $null }
    $t=$tasks[0]
    if ($t.Description -cne ('WiFiProxySwitcher-v1|'+$Manifest.OwnerSid+'|'+$Manifest.Root) -or $t.Principal.UserId -notin @($Manifest.OwnerSid,[Security.Principal.WindowsIdentity]::GetCurrent().Name)) { throw '同名任务不属于本次安装，拒绝修改' }
    return $t
}
function Stop-OwnedWatcher($Manifest) {
    $task=Get-OwnedTask $Manifest
    if ($null -ne $task) { Disable-ScheduledTask -TaskName $Manifest.TaskName -TaskPath '\' -ErrorAction Stop | Out-Null }
    [IO.File]::WriteAllText((Join-Path $Manifest.Root 'state\stop.request'),'stop',[Text.UTF8Encoding]::new($true))
    $watch=New-UserMutex 'Watcher'; $taken=$false
    try {
        $taken=Enter-Mutex $watch 15000
        if (-not $taken -and $null -ne $task) {
            Stop-ScheduledTask -TaskName $Manifest.TaskName -TaskPath '\' -ErrorAction Stop
            $taken=Enter-Mutex $watch 10000
        }
        if (-not $taken) { throw '监控仍持有锁，拒绝恢复或卸载；请查看任务计划程序后重试' }
        # A task launcher may be starting before the watcher takes its mutex. Stop the owned task as well.
        if ($null -ne $task) {
            $latest=Get-OwnedTask $Manifest
            if ($latest.State -in @('Running','Queued')) { Stop-ScheduledTask -TaskName $Manifest.TaskName -TaskPath '\' -ErrorAction Stop }
        }
    } finally { if ($taken) { $watch.ReleaseMutex() }; $watch.Dispose() }
}
function Start-OwnedWatcher($Manifest) {
    $task=Get-OwnedTask $Manifest
    if ($null -eq $task) { throw '自启动任务缺失，请重复安装以修复' }
    $watch=New-UserMutex 'Watcher'; $taken=$false
    try {
        $taken=Enter-Mutex $watch
        if (-not $taken) { Write-Output '已有监控实例运行，无需重复启动'; return }
        $stop=Join-Path $Manifest.Root 'state\stop.request'
        if (Test-Path -LiteralPath $stop) { Remove-Item -LiteralPath $stop -Force }
        Enable-ScheduledTask -TaskName $Manifest.TaskName -TaskPath '\' -ErrorAction Stop | Out-Null
        Start-ScheduledTask -TaskName $Manifest.TaskName -TaskPath '\' -ErrorAction Stop
    } finally { if ($taken) { $watch.ReleaseMutex() }; $watch.Dispose() }
    $ready=$false
    for ($i=0;$i -lt 30;$i++) {
        Start-Sleep -Milliseconds 500
        $w=New-UserMutex 'Watcher'; $free=Enter-Mutex $w
        if ($free) { $w.ReleaseMutex() }; $w.Dispose()
        $statusPath=Join-Path $Manifest.Root 'state\status.json'
        if (-not $free -and (Test-Path -LiteralPath $statusPath)) {
            $s=Get-Content -LiteralPath $statusPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($s.Outcome -ne 'Starting' -and ([DateTimeOffset]::Now-[DateTimeOffset]::Parse($s.Time)).TotalSeconds -lt 15) { $ready=$true; break }
        }
    }
    if (-not $ready) { throw '任务已请求启动，但未收到监控就绪心跳。检查日志、执行策略、WSH 和任务历史' }
    Write-Output '监控已静默启动并收到心跳；网络/代理结果请用 Status.bat 与日志确认'
}
function Restore-OwnedProxy($Manifest) {
    $backupPath=Join-Path $Manifest.Root 'state\proxy-before-install.json'
    $original=Get-Content -LiteralPath $backupPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $current=Get-ManualSnapshot
    if (Test-RestoreAllowed $current $original) { Write-Output '当前配置已等于安装前配置'; return }
    $last=$null; $lastPath=Join-Path $Manifest.Root 'state\last-applied.json'
    if (Test-Path -LiteralPath $lastPath) { $last=Get-Content -LiteralPath $lastPath -Raw -Encoding UTF8 | ConvertFrom-Json }
    if (-not (Test-RestoreAllowed $current $last -Force:$ForceRestore)) { throw '检测到工具最后一次写入之后的代理变更或未完成写入。已停止监控；为保护后续修改，未恢复/删除安装。确认后使用 -ForceRestore；卸载也可用 -KeepCurrentProxy 保留当前配置' }
    Restore-ManualSnapshot $original
    Write-Output '已恢复安装前手动代理配置；PAC/自动检测保持当前设置'
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

try {
    Initialize-Windows
    if (-not [Environment]::Is64BitProcess) { throw '请使用 64 位 Windows PowerShell 5.1' }
    $mutex=New-UserMutex 'Control'; $owned=Enter-Mutex $mutex 30000
    if (-not $owned) { throw '其他安装/启动/停止操作正在进行，请稍后重试' }
    $root=Get-InstalledRoot
    if ($Action -eq 'Install') {
        if (-not $InstallDir) { if ($root) { $InstallDir=$root } else { $InstallDir=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'WiFiProxySwitcher' } }
        $InstallDir=[IO.Path]::GetFullPath($InstallDir).TrimEnd('\')
        Assert-PlainPath $InstallDir
        if ($root -and -not [string]::Equals($root,$InstallDir,[StringComparison]::OrdinalIgnoreCase)) { throw '已有另一安装目录，请先卸载，再改变目录' }
        if ($root) { $InstallDir=$root }
        if ($InstallDir -match '["\r\n]' -or $InstallDir.StartsWith('\\') -or $InstallDir -eq [IO.Path]::GetPathRoot($InstallDir).TrimEnd('\')) { throw '安装目录必须是本地专用子目录，不能含引号或换行' }
        $source=[IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\')
        if ([string]::Equals($source,$InstallDir,[StringComparison]::OrdinalIgnoreCase)) {
            if (-not (Test-Path -LiteralPath (Join-Path $InstallDir 'state\installation.json'))) { throw '首次安装不能覆盖源代码目录，请使用默认目录' }
        }
        $existing=$false
        if (Test-Path -LiteralPath $InstallDir) {
            if ((Get-Item -LiteralPath $InstallDir).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw '安装目录不能为链接或联接点' }
            if (Test-Path -LiteralPath (Join-Path $InstallDir 'state\installation.json')) { $manifest=Read-Install $InstallDir; $existing=$true; Stop-OwnedWatcher $manifest }
            elseif (@(Get-ChildItem -LiteralPath $InstallDir -Force).Count) { throw '目标目录不是空目录，拒绝覆盖用户文件' }
        }
        Read-Configuration (Join-Path $source 'config.json') | Out-Null
        Assert-ProxyPolicy
        [IO.Directory]::CreateDirectory($InstallDir) | Out-Null
        Protect-InstallDirectory $InstallDir
        [IO.Directory]::CreateDirectory((Join-Path $InstallDir 'state')) | Out-Null
        $files=@('Control.ps1','ProxyWatcher.ps1','SilentLauncher.vbs','config.json','README.md','Install.bat','Start.bat','Stop.bat','Uninstall.bat','RestoreProxy.bat','Status.bat','lib\Core.ps1','lib\Windows.ps1','lib\Native.cs')
        if ($existing) { $files=@($files | Where-Object { $_ -ne 'config.json' }) }
        foreach ($relative in $files) {
            $src=Join-Path $source $relative; $dst=Join-Path $InstallDir $relative
            Assert-PlainPath $dst
            if (-not [string]::Equals($src,$dst,[StringComparison]::OrdinalIgnoreCase)) { [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($dst)) | Out-Null; Copy-Item -LiteralPath $src -Destination $dst -Force }
        }
        $backup=Join-Path $InstallDir 'state\proxy-before-install.json'
        if (-not $existing) {
            Write-JsonAtomic $backup (Get-ManualSnapshot)
            Write-JsonAtomic (Join-Path $InstallDir 'state\last-applied.json') (Get-ManualSnapshot)
        } elseif (-not (Test-Path -LiteralPath $backup)) { throw '原配置备份丢失，拒绝重新覆盖备份' }
        $manifest=[pscustomobject]@{ Product='WiFiProxySwitcher-v1'; Root=$InstallDir; OwnerSid=(Get-UserSid); TaskName=($script:TaskPrefix+(Get-UserSid)); Files=@() }
        foreach ($relative in @('Control.ps1','ProxyWatcher.ps1','SilentLauncher.vbs','config.json','README.md','Install.bat','Start.bat','Stop.bat','Uninstall.bat','RestoreProxy.bat','Status.bat','lib\Core.ps1','lib\Windows.ps1','lib\Native.cs')) {
            $manifest.Files += [pscustomobject]@{ Path=$relative; Hash=(Get-FileHash -LiteralPath (Join-Path $InstallDir $relative) -Algorithm SHA256).Hash }
        }
        Get-OwnedTask $manifest | Out-Null
        Write-JsonAtomic (Join-Path $InstallDir 'state\installation.json') $manifest
        $k=[Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($script:Pointer)
        try { $k.SetValue('InstallDir',$InstallDir,[Microsoft.Win32.RegistryValueKind]::String) } finally { $k.Dispose() }
        $exe=Join-Path $env:SystemRoot 'System32\wscript.exe'
        $args='//B //Nologo "'+(Join-Path $InstallDir 'SilentLauncher.vbs')+'" Watch'
        $taskAction=New-ScheduledTaskAction -Execute $exe -Argument $args -WorkingDirectory $InstallDir
        $trigger=New-ScheduledTaskTrigger -AtLogOn -User $manifest.OwnerSid
        $principal=New-ScheduledTaskPrincipal -UserId $manifest.OwnerSid -LogonType Interactive -RunLevel Limited
        $settings=New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit ([TimeSpan]::Zero)
        Register-ScheduledTask -TaskName $manifest.TaskName -TaskPath '\' -Action $taskAction -Trigger $trigger -Principal $principal -Settings $settings -Description ('WiFiProxySwitcher-v1|'+$manifest.OwnerSid+'|'+$InstallDir) -Force -ErrorAction Stop | Out-Null
        Start-OwnedWatcher $manifest
        Write-Output ('安装位置: '+$InstallDir)
    } elseif (-not $root) {
        if ($Action -in @('Stop','Uninstall','Restore','Status')) { Write-Output '当前用户未安装本工具，无需操作' } else { throw '尚未安装' }
    } else {
        $manifest=Read-Install $root
        switch ($Action) {
            'Start' { Start-OwnedWatcher $manifest }
            'Stop' { Stop-OwnedWatcher $manifest; Write-Output '监控与登录任务已停止/禁用；代理保持当前状态，恢复请用 RestoreProxy.bat' }
            'Restore' { Stop-OwnedWatcher $manifest; Restore-OwnedProxy $manifest }
            'Status' {
                $task=Get-OwnedTask $manifest
                $actual=[WiFiProxy.Native]::ReadProxy(); $server='<已有地址省略>'
                if ($actual.Server -match '^([0-9]{1,3}\.){3}[0-9]{1,3}:[0-9]{1,5}$') { $server=$actual.Server }
                $w=New-UserMutex 'Watcher'; $free=Enter-Mutex $w; if ($free) { $w.ReleaseMutex() }; $w.Dispose()
                $taskState='Missing'; $lastResult=$null
                if ($null -ne $task) { $taskState=[string]$task.State; $lastResult=(Get-ScheduledTaskInfo -TaskName $manifest.TaskName -TaskPath '\' -ErrorAction Stop).LastTaskResult }
                $heartbeat=$null; $p=Join-Path $root 'state\status.json'; if (Test-Path -LiteralPath $p) { $heartbeat=Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json }
                [pscustomobject]@{ InstallDir=$root; TaskName=$manifest.TaskName; TaskState=$taskState; LastTaskResult=$lastResult; WatcherRunning=(-not $free); ManualProxyEnabled=$actual.Enable; ProxyServer=$server; LocalBypass=($actual.Bypass -split ';' -contains '<local>'); AutomaticProxyFlags=($actual.Flags -band 12); Heartbeat=$heartbeat } | ConvertTo-Json -Depth 6
            }
            'Uninstall' {
                if ($ForceRestore -and $KeepCurrentProxy) { throw '-ForceRestore 与 -KeepCurrentProxy 不能同时使用' }
                Stop-OwnedWatcher $manifest
                if (-not $KeepCurrentProxy) { Restore-OwnedProxy $manifest } else { Write-Output '根据明确选项保留当前代理配置' }
                $task=Get-OwnedTask $manifest
                if ($null -ne $task) { Unregister-ScheduledTask -TaskName $manifest.TaskName -TaskPath '\' -Confirm:$false -ErrorAction Stop }
                foreach ($entry in $manifest.Files) {
                    # Treat manifest paths as data; never allow traversal or deleting arbitrary files.
                    if ($entry.Path -notin @('Control.ps1','ProxyWatcher.ps1','SilentLauncher.vbs','config.json','README.md','Install.bat','Start.bat','Stop.bat','Uninstall.bat','RestoreProxy.bat','Status.bat','lib\Core.ps1','lib\Windows.ps1','lib\Native.cs')) { throw '安装清单存在未知路径，拒绝删除' }
                    $p=Join-Path $root $entry.Path
                    Assert-PlainPath $p
                    if (Test-Path -LiteralPath $p) { if ((Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash -ceq $entry.Hash) { Remove-Item -LiteralPath $p -Force } else { Write-Output ('文件被用户修改，保留: '+$entry.Path) } }
                }
                foreach ($name in @('installation.json','stop.request','status.json','last-applied.json','proxy-before-install.json')) { $p=Join-Path $root ('state\'+$name); if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force } }
                if ($DeleteLogs) { Get-ChildItem -LiteralPath (Join-Path $root 'logs') -Filter 'watcher.jsonl*' -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^watcher\.jsonl(\.[0-9]+)?$' } | Remove-Item -Force }
                foreach ($sub in @('lib','state','logs','')) { $p=$root; if ($sub) { $p=Join-Path $root $sub }; if ((Test-Path -LiteralPath $p) -and -not @(Get-ChildItem -LiteralPath $p -Force).Count) { Remove-Item -LiteralPath $p -Force } }
                if ((Get-InstalledRoot) -ceq $root) { [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKey($script:Pointer,$false) }
                Write-Output '卸载完成。默认保留日志和用户改动的文件；未删除目录中的其他文件'
            }
        }
    }
} catch {
    $code=1
    if ($Quiet) {
        try {
            $dir=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'WiFiProxySwitcher-Control'
            [IO.Directory]::CreateDirectory($dir) | Out-Null; $path=Join-Path $dir 'control-errors.log'
            if ((Test-Path -LiteralPath $path) -and (Get-Item -LiteralPath $path).Length -gt 262144) { Move-Item -LiteralPath $path -Destination ($path+'.1') -Force }
            [IO.File]::AppendAllText($path,([DateTimeOffset]::Now.ToString('o')+' '+$Action+' '+$_.Exception.Message+[Environment]::NewLine),[Text.UTF8Encoding]::new($true))
        } catch {}
    } else { Write-Error $_ -ErrorAction Continue }
} finally { if ($owned) { $mutex.ReleaseMutex() }; if ($null -ne $mutex) { $mutex.Dispose() } }
exit $code

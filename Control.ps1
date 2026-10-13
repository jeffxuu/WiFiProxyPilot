#requires -Version 5.1
[CmdletBinding()]
param(
    [ValidateSet('Install','Start','Stop','Uninstall','Restore','Status','Check','Pause','Resume','Direct','Settings')][string]$Action='Status',
    [string]$InstallDir='',
    [switch]$ForceRestore,
    [switch]$KeepCurrentProxy,
    [switch]$DeleteLogs,
    [switch]$Quiet,
    [string]$DesktopSource='',
    [string]$SetupConfigPath='',
    [string]$ResultPath=''
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'lib\Core.ps1')
. (Join-Path $PSScriptRoot 'lib\Windows.ps1')
. (Join-Path $PSScriptRoot 'lib\Lifecycle.ps1')
. (Join-Path $PSScriptRoot 'lib\Desktop.ps1')
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
$result=[ordered]@{Succeeded=$false;Code='';Message='';Data=$null}
$script:Pointer='Software\WiFiProxySwitcher'
$script:TaskPrefix='WiFiProxySwitcher-'
$mutex=$null; $owned=$false; $code=0

function Assert-ManagementEngineProtocol([string]$Root) {
    $message='需要升级后台组件：无法确认正在运行的引擎支持持久管理意图。请先执行修复/升级安装，真正停止旧监控并启动新版；现有规则与最初代理备份将保留'
    $engine=Join-Path $Root 'ProxyWatcher.ps1'; Assert-PlainPath $engine
    if (-not [IO.File]::ReadAllText($engine).Contains('$script:EngineProtocol=2')) { Throw-ProductError 'EngineUpgradeRequired' $message }
    $watch=New-UserMutex 'Watcher'; $free=$false
    try { $free=Enter-Mutex $watch; if ($free) { $watch.ReleaseMutex() } } finally { $watch.Dispose() }
    # The disk can be newer than a process already holding the watcher lock. Its live heartbeat
    # must confirm the protocol before any intent change or fresh-scan request is persisted.
    if ($free) { return }
    try {
        $path=Join-Path $Root 'state/status.json'; Assert-PlainPath $path
        $bytes=Read-ConfigurationBytes $path
        if ($bytes.Length -gt 65536) { throw '监控状态文件过大' }
        $heartbeat=([Text.UTF8Encoding]::new($false,$true).GetString($bytes).TrimStart([char]0xFEFF)) | ConvertFrom-Json
        foreach ($name in @('SchemaVersion','EngineVersion','Time','Outcome','RunId')) { if ($null -eq $heartbeat.PSObject.Properties[$name]) { throw '缺少运行协议字段' } }
        $schema=0; $version=$null
        if (-not [int]::TryParse([string]$heartbeat.SchemaVersion,[ref]$schema) -or $schema -lt 2 -or -not [Version]::TryParse(([string]$heartbeat.EngineVersion).Split('-')[0],[ref]$version) -or $version -lt [Version]'3.2') { throw '运行中的引擎版本过旧' }
        if ([string]::IsNullOrEmpty([string]$heartbeat.RunId) -or $heartbeat.Outcome -eq 'Stopped') { throw '没有可确认的运行实例' }
        $age=([DateTimeOffset]::Now-(ConvertTo-RecordTime $heartbeat.Time)).TotalSeconds
        $poll=5
        if ($null -ne $heartbeat.PSObject.Properties['PollSeconds']) { $value=0; if ([int]::TryParse([string]$heartbeat.PollSeconds,[ref]$value) -and $value -ge 1 -and $value -le 300) { $poll=$value } }
        if ($age -lt -5 -or $age -ge [Math]::Max(30,2*$poll+15)) { throw '运行心跳已过期或时间异常' }
    } catch {
        $failure=[InvalidOperationException]::new($message+'。详情：'+$_.Exception.Message)
        $failure.Data['WiFiProxyCode']='EngineUpgradeRequired'
        throw $failure
    }
}


try {
    Initialize-Windows
    if (-not [Environment]::Is64BitProcess) { throw '请使用 64 位 Windows PowerShell 5.1' }
    $mutex=New-UserMutex 'Control'; $owned=Enter-Mutex $mutex 30000
    if (-not $owned) { throw '其他安装/启动/停止操作正在进行，请稍后重试' }
    $root=Get-InstalledRoot
    if (-not $root -and $InstallDir -and $Action -ne 'Install') { $root=[IO.Path]::GetFullPath($InstallDir).TrimEnd('\') }
    if ($Action -eq 'Install') {
        if (-not $InstallDir) { if ($root) { $InstallDir=$root } else { $InstallDir=Get-DefaultEngineInstallDirectory } }
        $InstallDir=[IO.Path]::GetFullPath($InstallDir).TrimEnd('\')
        Assert-PlainPath $InstallDir
        if ($root -and -not [string]::Equals($root,$InstallDir,[StringComparison]::OrdinalIgnoreCase)) { throw '已有另一安装目录，请先卸载，再改变目录' }
        if ($root) { $InstallDir=$root }
        if ($InstallDir -match '%[^%]+%') { throw '任务计划程序会展开成对 %NAME% 路径，请选择不含这种结构的安装目录' }
        if ($InstallDir -match '["\r\n]' -or $InstallDir.StartsWith('\\') -or $InstallDir -eq [IO.Path]::GetPathRoot($InstallDir).TrimEnd('\')) { throw '安装目录必须是本地专用子目录，不能含引号或换行' }
        $source=[IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\')
        if ([string]::Equals($source,$InstallDir,[StringComparison]::OrdinalIgnoreCase)) {
            if (-not (Test-Path -LiteralPath (Join-Path $InstallDir 'state\installation.json'))) { throw '首次安装不能覆盖源代码目录，请使用默认目录' }
        }
        $previous=$null
        if (Test-Path -LiteralPath $InstallDir) {
            if ((Get-Item -LiteralPath $InstallDir).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw '安装目录不能为链接或联接点' }
            if (Test-Path -LiteralPath (Join-Path $InstallDir 'state\installation.json')) { $previous=Read-Install $InstallDir }
            elseif (@(Get-ChildItem -LiteralPath $InstallDir -Force).Count) { throw '目标目录不是空目录，拒绝覆盖用户文件' }
        }
        $manifest=Install-ProductFiles $source $InstallDir $previous $SetupConfigPath
        if ($DesktopSource -and $null -eq (Read-InstallerDesktop)) { Install-DesktopFiles $InstallDir $DesktopSource | Out-Null }
        $k=[Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($script:Pointer)
        try { $k.SetValue('InstallDir',$InstallDir,[Microsoft.Win32.RegistryValueKind]::String) } finally { $k.Dispose() }
        $exe=Join-Path $env:SystemRoot 'System32\wscript.exe'
        $taskArguments='//B //Nologo ".\SilentLauncher.vbs" Watch'
        $taskAction=New-ScheduledTaskAction -Execute $exe -Argument $taskArguments -WorkingDirectory $InstallDir
        $trigger=New-ScheduledTaskTrigger -AtLogOn -User $manifest.OwnerSid
        $principal=New-ScheduledTaskPrincipal -UserId $manifest.OwnerSid -LogonType Interactive -RunLevel Limited
        $settings=New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit ([TimeSpan]::Zero)
        Register-ScheduledTask -TaskName $manifest.TaskName -TaskPath '\' -Action $taskAction -Trigger $trigger -Principal $principal -Settings $settings -Description ('WiFiProxySwitcher-v1|'+$manifest.OwnerSid+'|'+$InstallDir) -Force -ErrorAction Stop | Out-Null
        Start-OwnedWatcher $manifest
        Apply-LoginSettings $InstallDir $manifest
        $result.Data=@{InstallDir=$InstallDir}; Write-Output ('安装位置: '+$InstallDir)
    } elseif (-not $root) {
        if ($Action -in @('Stop','Uninstall','Restore','Status','Check')) { Write-Output '当前用户未安装本工具，无需操作' } else { throw '尚未安装' }
    } elseif ($Action -eq 'Uninstall' -and -not (Test-Path -LiteralPath (Join-Path $root 'state/installation.json')) -and (Test-Path -LiteralPath (Join-Path $root 'app/desktop.json'))) {
        Remove-DesktopFiles (Read-DesktopInstall $root)
    } else {
        $manifest=Read-Install $root
        if ($Action -in @('Pause','Resume','Direct','Start','Check')) {
            Assert-ManagementEngineProtocol $root
        }
        switch ($Action) {
            'Pause' { Set-ManagementIntent $root 'Paused' | Out-Null; Write-Output '自动切换已暂停；当前手动代理可能继续生效。退出、锁屏、注销和重启后保持暂停' }
            'Resume' {
                Set-ManagementIntent $root 'Monitoring' | Out-Null
                $w=New-UserMutex 'Watcher'; $free=Enter-Mutex $w; if ($free) { $w.ReleaseMutex() }; $w.Dispose()
                if ($free) { Start-OwnedWatcher $manifest }
                Write-JsonAtomic (Join-Path $root 'state/check.request') @{Time=[DateTimeOffset]::Now.ToString('o');RequestId=[Guid]::NewGuid().ToString('N')}
                Apply-LoginSettings $root $manifest
            }
            'Direct' { Set-OwnedDirectMode $manifest }
            'Settings' { Apply-LoginSettings $root $manifest }
            'Check' {
                $w=New-UserMutex 'Watcher'; $free=Enter-Mutex $w; if ($free) { $w.ReleaseMutex() }; $w.Dispose()
                if ($free) { throw '请先启动监控，再立即检测' }
                $request=[Guid]::NewGuid().ToString('N')
                Write-JsonAtomic (Join-Path $root 'state/check.request') @{Time=[DateTimeOffset]::Now.ToString('o');RequestId=$request}
                $result.Data=@{RequestId=$request}
                Write-Output '已请求立即检测；稳定性检查和 Strict/Safe 规则保持不变'
            }
            'Start' { Set-ManagementIntent $root 'Monitoring' | Out-Null; Start-OwnedWatcher $manifest; Apply-LoginSettings $root $manifest }
            'Stop' { Set-ManagementIntent $root 'Paused' | Out-Null; Stop-OwnedWatcher $manifest; Write-Output '监控与登录任务已停止/禁用；已保存暂停意图，代理保持当前状态' }
            'Restore' { Set-ManagementIntent $root 'Paused' | Out-Null; Stop-OwnedWatcher $manifest; Restore-OwnedProxy $manifest -Force:$ForceRestore }
            'Status' {
                $task=Get-OwnedTask $manifest
                $actual=Read-SystemProxy; $server='<已有地址省略>'
                if ($actual.Server -match '^([0-9]{1,3}\.){3}[0-9]{1,3}:[0-9]{1,5}$') { $server=$actual.Server }
                $w=New-UserMutex 'Watcher'; $free=Enter-Mutex $w; if ($free) { $w.ReleaseMutex() }; $w.Dispose()
                $taskState='Missing'; $lastResult=$null
                if ($null -ne $task) { $taskState=[string]$task.State; $lastResult=(Get-ScheduledTaskInfo -TaskName $manifest.TaskName -TaskPath '\' -ErrorAction Stop).LastTaskResult }
                $heartbeat=$null; $p=Join-Path $root 'state\status.json'; if (Test-Path -LiteralPath $p) { $heartbeat=Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json }
                $status=[pscustomobject]@{ InstallDir=$root; TaskName=$manifest.TaskName; TaskState=$taskState; LastTaskResult=$lastResult; WatcherRunning=(-not $free); ManualProxyEnabled=$actual.Enable; ProxyServer=$server; LocalBypass=(@($actual.Bypass -split ';' | Where-Object {$_.Trim() -ieq '<local>'}).Count -gt 0); AutomaticProxyFlags=($actual.Flags -band 12); Heartbeat=$heartbeat }
                $result.Data=$status
                if ($Quiet) { Write-JsonAtomic (Join-Path $root 'state/control-status.json') $status } else { $status | ConvertTo-Json -Depth 6 }
            }
            'Uninstall' {
                if ($null -ne (Read-InstallerDesktop)) { throw 'This application is owned by Windows Setup. Use Installed apps to uninstall WiFi Proxy Pilot.' }
                if ($ForceRestore -and $KeepCurrentProxy) { throw '-ForceRestore 与 -KeepCurrentProxy 不能同时使用' }
                $desktop=Read-DesktopInstall $root
                Uninstall-Product $manifest -KeepCurrentProxy:$KeepCurrentProxy -DeleteLogs:$DeleteLogs -ForceRestore:$ForceRestore
                Remove-DesktopFiles $desktop
            }
        }
    }
} catch {
    $code=1
    $result.Message=$_.Exception.Message; $result.Code='OperationFailed'
    if ($_.Exception.Data.Contains('WiFiProxyCode')) { $result.Code=[string]$_.Exception.Data['WiFiProxyCode']; if ($result.Code -eq 'RestoreConflict') { $code=20 } }
    Write-ControlFailure $Action $_.Exception.Message
    if (-not $Quiet) { Write-Error $_ -ErrorAction Continue }
} finally { if ($owned) { $mutex.ReleaseMutex() }; if ($null -ne $mutex) { $mutex.Dispose() } }
if ($ResultPath) {
    try { $result.Succeeded=($code -eq 0); Write-JsonAtomic $ResultPath $result } catch { Write-ControlFailure 'Result' $_.Exception.Message; $code=1 }
}
exit $code

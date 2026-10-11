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
. (Join-Path $PSScriptRoot 'lib\Lifecycle.ps1')
$script:Pointer='Software\WiFiProxySwitcher'
$script:TaskPrefix='WiFiProxySwitcher-'
$mutex=$null; $owned=$false; $code=0


try {
    Initialize-Windows
    if (-not [Environment]::Is64BitProcess) { throw '请使用 64 位 Windows PowerShell 5.1' }
    $mutex=New-UserMutex 'Control'; $owned=Enter-Mutex $mutex 30000
    if (-not $owned) { throw '其他安装/启动/停止操作正在进行，请稍后重试' }
    $root=Get-InstalledRoot
    if (-not $root -and $InstallDir -and $Action -ne 'Install') { $root=[IO.Path]::GetFullPath($InstallDir).TrimEnd('\') }
    if ($Action -eq 'Install') {
        if (-not $InstallDir) { if ($root) { $InstallDir=$root } else { $InstallDir=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'WiFiProxySwitcher' } }
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
        $manifest=Install-ProductFiles $source $InstallDir $previous
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
        Write-Output ('安装位置: '+$InstallDir)
    } elseif (-not $root) {
        if ($Action -in @('Stop','Uninstall','Restore','Status')) { Write-Output '当前用户未安装本工具，无需操作' } else { throw '尚未安装' }
    } else {
        $manifest=Read-Install $root
        switch ($Action) {
            'Start' { Start-OwnedWatcher $manifest }
            'Stop' { Stop-OwnedWatcher $manifest; Write-Output '监控与登录任务已停止/禁用；代理保持当前状态，恢复请用 RestoreProxy.bat' }
            'Restore' { Stop-OwnedWatcher $manifest; Restore-OwnedProxy $manifest -Force:$ForceRestore }
            'Status' {
                $task=Get-OwnedTask $manifest
                $actual=Read-SystemProxy; $server='<已有地址省略>'
                if ($actual.Server -match '^([0-9]{1,3}\.){3}[0-9]{1,3}:[0-9]{1,5}$') { $server=$actual.Server }
                $w=New-UserMutex 'Watcher'; $free=Enter-Mutex $w; if ($free) { $w.ReleaseMutex() }; $w.Dispose()
                $taskState='Missing'; $lastResult=$null
                if ($null -ne $task) { $taskState=[string]$task.State; $lastResult=(Get-ScheduledTaskInfo -TaskName $manifest.TaskName -TaskPath '\' -ErrorAction Stop).LastTaskResult }
                $heartbeat=$null; $p=Join-Path $root 'state\status.json'; if (Test-Path -LiteralPath $p) { $heartbeat=Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json }
                $status=[pscustomobject]@{ InstallDir=$root; TaskName=$manifest.TaskName; TaskState=$taskState; LastTaskResult=$lastResult; WatcherRunning=(-not $free); ManualProxyEnabled=$actual.Enable; ProxyServer=$server; LocalBypass=(@($actual.Bypass -split ';' | Where-Object {$_.Trim() -ieq '<local>'}).Count -gt 0); AutomaticProxyFlags=($actual.Flags -band 12); Heartbeat=$heartbeat }
                if ($Quiet) { Write-JsonAtomic (Join-Path $root 'state/control-status.json') $status } else { $status | ConvertTo-Json -Depth 6 }
            }
            'Uninstall' {
                if ($ForceRestore -and $KeepCurrentProxy) { throw '-ForceRestore 与 -KeepCurrentProxy 不能同时使用' }
                Uninstall-Product $manifest -KeepCurrentProxy:$KeepCurrentProxy -DeleteLogs:$DeleteLogs -ForceRestore:$ForceRestore
            }
        }
    }
} catch {
    $code=1
    Write-ControlFailure $Action $_.Exception.Message
    if (-not $Quiet) { Write-Error $_ -ErrorAction Continue }
} finally { if ($owned) { $mutex.ReleaseMutex() }; if ($null -ne $mutex) { $mutex.Dispose() } }
exit $code

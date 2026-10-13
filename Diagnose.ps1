#requires -Version 5.1
[CmdletBinding()]
param([string]$OutputPath='',[switch]$Probe,[switch]$Quiet)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'lib/Core.ps1')
. (Join-Path $PSScriptRoot 'lib/Windows.ps1')
. (Join-Path $PSScriptRoot 'lib/Lifecycle.ps1')
$checks=[Collections.Generic.List[object]]::new(); $exitCode=0
function Add-Check([string]$Name,[string]$Status,$Detail) { $checks.Add([pscustomobject]@{Name=$Name;Status=$Status;Detail=$Detail}) }
function Run-Check([string]$Name,[scriptblock]$Body) {
    try { $detail=& $Body; Add-Check $Name 'Pass' $detail } catch { Add-Check $Name 'Fail' $_.Exception.Message }
}
try {
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'Windows 平台诊断只能在真实 Windows 上运行；本次未调用 WLAN/WinINet/注册表/任务 API' }
    Initialize-Windows
    Run-Check 'Windows/PowerShell/用户会话' {
        $os=Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        [pscustomobject]@{Windows=$os.Caption;Build=$os.BuildNumber;PowerShell=$PSVersionTable.PSVersion.ToString();Edition=$PSVersionTable.PSEdition;Is64Bit=[Environment]::Is64BitProcess;UserSid=(Get-UserSid);SessionId=[Diagnostics.Process]::GetCurrentProcess().SessionId;LanguageMode=[string]$ExecutionContext.SessionState.LanguageMode}
    }
    Run-Check '执行策略（只读）' { Get-ExecutionPolicy -List | Select-Object Scope,ExecutionPolicy }
    Run-Check 'WSH 文件与启用策略（不启动任务）' {
        $exe=Join-Path $env:SystemRoot 'System32/wscript.exe'
        if (-not (Test-Path -LiteralPath $exe)) { throw 'wscript.exe 不存在' }
        foreach ($hive in @([Microsoft.Win32.Registry]::CurrentUser,[Microsoft.Win32.Registry]::LocalMachine)) {
            $key=$hive.OpenSubKey('Software\Microsoft\Windows Script Host\Settings')
            if ($null -ne $key) { try { if ($key.GetValue('Enabled',1) -eq 0) { throw 'Windows Script Host 被策略禁用' } } finally { $key.Dispose() } }
        }
        '文件存在且未发现 WSH Enabled=0；WDAC/AppLocker/实际隐藏启动仍需验收'
    }
    Run-Check '代理管理策略' { Assert-ProxyPolicy; '未发现本工具检查范围内的代理管理策略' }
    Run-Check 'WinINet 与 HKCU 手动值（脱敏，只读）' {
        $actual=Read-SystemProxy; $reg=Get-ManualSnapshot
        $server='<原代理字符串省略>'; if ($actual.Server -match '^([0-9]{1,3}\.){3}[0-9]{1,3}:[0-9]{1,5}$' -or -not $actual.Server) { $server=$actual.Server }
        [pscustomobject]@{ApiEnabled=$actual.Enable;RegistryEnabled=$reg.ProxyEnable.Value;RegistryEnableExists=$reg.ProxyEnable.Exists;Server=$server;ApiRegistryServerEqual=($actual.Server -ceq [string]$reg.ProxyServer.Value);LocalBypass=(@($actual.Bypass -split ';' | Where-Object { $_.Trim() -ieq '<local>' }).Count -gt 0);AutomaticFlags=($actual.Flags -band 12);PacConfigured=([bool]$actual.Pac)}
        if ([int]$reg.ProxyEnable.Value -ne [int]$actual.Enable -or ($reg.ProxyServer.Exists -and $actual.Server -cne [string]$reg.ProxyServer.Value) -or ($reg.ProxyOverride.Exists -and $actual.Bypass -cne [string]$reg.ProxyOverride.Value)) { throw 'WinINet 与 HKCU 回读不一致，请检查其他代理软件、组策略和刷新传播' }
        if (($actual.Flags -band 12) -ne 0 -or $actual.Pac) { Add-Check 'PAC/WPAD 优先级' 'Warn' '自动代理可能优先于手动代理；本工具不更改自动代理设置' }
    }
    $script:diagSnapshot=$null
    Run-Check 'WLAN 服务与 SSID/IPv4 网关快照' {
        $service=Get-Service WlanSvc -ErrorAction Stop
        if ($service.Status -ne 'Running') { throw ('WLAN AutoConfig 服务状态: '+$service.Status) }
        $native=[WiFiProxy.Native]::new()
        try { $script:diagSnapshot=Get-NetworkSnapshot $native } finally { $native.Dispose() }
        if ($script:diagSnapshot.Kind -eq 'Unknown') { throw $script:diagSnapshot.Reason }
        $script:diagSnapshot
    }
    $root=Get-InstalledRoot; $manifest=$null; $c=$null
    Run-Check '配置' {
        $configRoot=$PSScriptRoot; if ($root) { $configRoot=$root }
        $script:diagConfig=Read-Configuration (Join-Path $configRoot 'config.json')
        [pscustomobject]@{Mode=$script:diagConfig.Mode;Port=$script:diagConfig.Port;PollSeconds=$script:diagConfig.PollSeconds;Diagnostics=$script:diagConfig.Diagnostics}
    }
    if ($root) {
        Run-Check '任务原始身份字段（只读，归属校验前采集）' {
            $m=Read-Install $root; $candidate=Get-ProductTask $m
            if ($null -eq $candidate) { throw '安装存在，但自启动任务缺失' }
            Get-TaskOwnershipDetails $candidate $m
        }
        Run-Check '安装记录/任务归属/心跳' {
            $m=Read-Install $root; $t=Get-OwnedTask $m
            if ($null -eq $t) { throw '安装存在，但自启动任务缺失' }
            $info=Get-ScheduledTaskInfo -TaskName $m.TaskName -TaskPath '\' -ErrorAction Stop
            $w=New-UserMutex 'Watcher'; $free=Enter-Mutex $w; if ($free) { $w.ReleaseMutex() }; $w.Dispose()
            $heartbeat=$null; $age=$null; $hp=Join-Path $root 'state/status.json'
            if (Test-Path -LiteralPath $hp) { $heartbeat=Get-Content -LiteralPath $hp -Raw -Encoding UTF8 | ConvertFrom-Json; $age=([DateTimeOffset]::Now-(ConvertTo-RecordTime $heartbeat.Time)).TotalSeconds }
            $ageLimit=30
            if ($null -ne (Get-Variable diagConfig -Scope Script -ErrorAction SilentlyContinue)) { $ageLimit=[Math]::Max(30,$script:diagConfig.PollSeconds+3*$script:diagConfig.DiagnosticTimeoutMilliseconds/1000.0+5) }
            if (-not $free -and ($null -eq $age -or $age -gt $ageLimit -or $age -lt 0)) { Add-Check '监控心跳新鲜度' 'Warn' '进程锁存在但心跳过期/时间异常，请检查日志与进程' }
            [pscustomobject]@{InstallDir=$root;TaskName=$m.TaskName;TaskState=[string]$t.State;LastTaskResult=$info.LastTaskResult;WatcherRunning=(-not $free);HeartbeatAgeSeconds=$age;Heartbeat=$heartbeat;Settings=$t.Settings | Select-Object MultipleInstances,ExecutionTimeLimit,RestartCount,RestartInterval,DisallowStartIfOnBatteries,StopIfGoingOnBatteries}
        }
    } else { Add-Check '安装/登录任务' 'NotRun' '当前用户尚未安装，可先检查网络与权限，再运行 Install.bat' }
    if ($null -ne $script:diagSnapshot -and $null -ne (Get-Variable diagConfig -Scope Script -ErrorAction SilentlyContinue)) {
        $target=Get-Target $script:diagSnapshot $script:diagConfig
        Add-Check '根据当前网络计算的目标（没有写入）' $(if ($target.Action -eq 'Keep') {'Warn'} else {'Pass'}) $target
        if ($Probe -and $target.Action -eq 'Enable' -and $script:diagConfig.Diagnostics -ne 'None') {
            $result=Test-ProxyEndpoint $target.Gateway $script:diagConfig
            Add-Check '可选代理服务诊断' $(if ($result.Health -eq 'Unavailable') {'Warn'} else {'Pass'}) $result
        } else { Add-Check '可选代理服务诊断' 'NotRun' '使用 -Probe 明确开启；需非白名单有效网关及已启用 Diagnostics' }
    }
} catch { Add-Check '诊断初始化' 'Fail' $_.Exception.Message }
if (@($checks | Where-Object { $_.Status -eq 'Fail' }).Count) { $exitCode=1 }
$report=[pscustomobject]@{Time=[DateTimeOffset]::Now.ToString('o');ReadOnly=$true;ProxyWritten=$false;Checks=$checks.ToArray();ExitCode=$exitCode}
try {
    if (-not $OutputPath) { $OutputPath=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'WiFiProxySwitcher-Control/diagnostics.json' }
    $OutputPath=[IO.Path]::GetFullPath($OutputPath); Assert-PlainPath $OutputPath
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($OutputPath)) | Out-Null
    Write-JsonAtomic $OutputPath $report
    if (-not $Quiet) { $report | ConvertTo-Json -Depth 12; Write-Output ('诊断报告: '+$OutputPath) }
} catch { Write-Error ('诊断报告写入失败: '+$_.Exception.Message) -ErrorAction Continue; $exitCode=1 }
exit $exitCode

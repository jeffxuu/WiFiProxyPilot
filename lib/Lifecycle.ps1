Set-StrictMode -Version 2.0
$script:Pointer='Software\WiFiProxySwitcher'
$script:TaskPrefix='WiFiProxySwitcher-'

function Get-ProductFiles {
    # Historical names remain valid ownership records; they are not shipped in the new payload.
    return @(@('Control.ps1','ProxyWatcher.ps1','Diagnose.ps1','SilentLauncher.vbs','config.json','README.md','tools/Install.bat','tools/Start.bat','tools/Stop.bat','tools/Uninstall.bat','tools/RestoreProxy.bat','tools/Status.bat','tools/Diagnose.bat','lib/Core.ps1','lib/Windows.ps1','lib/Native.cs','lib/Monitor.ps1','lib/Lifecycle.ps1','lib/Desktop.ps1','tests/Run-Tests.ps1','tests/Run-Tests.bat','tests/ProbeServer.cs','tests/Round2.Tests.ps1','tests/TaskOwnership.Tests.ps1','tests/Productization.Tests.ps1','docs/ARCHITECTURE.md','docs/WINDOWS_ACCEPTANCE.md','docs/TEST_RESULTS.md','docs/REVIEW_ROUND2.md','docs/TASK_OWNERSHIP_FIX.md','docs/test-results.json','docs/ADVANCED_USAGE.md','docs/PRODUCTIZATION.md','docs/PRODUCT_WINDOWS_ACCEPTANCE.md','docs/PRODUCT_TEST_RESULTS.md','docs/REPOSITORY_AUDIT_V3.md','docs/product-engine-tests.json','docs/product-launcher-tests.json','tests/V31.Tests.ps1','tools/Measure-Startup.ps1','docs/UI_DESIGN_V3_1.md','docs/TRAY_LIFECYCLE.md','docs/STARTUP_PERFORMANCE.md','docs/CONFIG_HOT_RELOAD.md','docs/TEST_RESULTS_V3_1.md','docs/CHANGES_V3_1.md')+@(Get-DistributionFiles) | Select-Object -Unique)
}
function Get-DistributionFiles {
    return @('Control.ps1','ProxyWatcher.ps1','Diagnose.ps1','SilentLauncher.vbs','config.json','README.md','README.zh-CN.md','LICENSE','tools/Install.bat','tools/Start.bat','tools/Stop.bat','tools/Uninstall.bat','tools/RestoreProxy.bat','tools/Status.bat','tools/Diagnose.bat','lib/Core.ps1','lib/Windows.ps1','lib/Native.cs','lib/Monitor.ps1','lib/Lifecycle.ps1','lib/Desktop.ps1','docs/PRODUCT_REQUIREMENTS.md','docs/INTERACTION_STATE_MACHINE.md','docs/UI_DESIGN_SYSTEM.md','docs/PERFORMANCE_V3_2.md','docs/CONFIG_MIGRATION.md','docs/TEST_RESULTS_V3_2.md','docs/RELEASE_CHECKLIST.md','docs/PUBLIC_REPOSITORY_AUDIT.md','docs/THIRD_PARTY_NOTICES.md','docs/licenses/DOTNET-RUNTIME-LICENSE.txt','docs/licenses/WINDOWS-DESKTOP-RUNTIME-LICENSE.txt','docs/licenses/WPF-UI-LICENSE.md','docs/licenses/WPF-UI-ThirdPartyNotices.txt')
}
function Assert-InstallManifest($Manifest) {
    $allowed=@(Get-ProductFiles)+@('Install.bat','Start.bat','Stop.bat','Uninstall.bat','RestoreProxy.bat','Status.bat','Diagnose.bat'); $seen=@{}
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
    foreach ($name in Get-DistributionFiles) {
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
    foreach ($name in Get-DistributionFiles) {
        $hash=(Get-FileHash -LiteralPath (Join-Path $FilesRoot $name) -Algorithm SHA256).Hash
        if ($null -ne $Previous -and ($name -eq 'config.json' -or $InPlace)) {
            $old=@($Previous.Files | Where-Object { $_.Path.Replace('\','/') -ceq $name })
            if ($old.Count -eq 1) { $hash=$old[0].Hash }
        }
        $manifest.Files += [pscustomobject]@{Path=$name;Hash=$hash}
    }
    # Keep ownership of historical shipped files so upgrades can still uninstall them safely.
    if ($null -ne $Previous) {
        foreach ($entry in $Previous.Files) {
            if (-not @($manifest.Files | Where-Object { $_.Path.Replace('\','/') -ceq $entry.Path.Replace('\','/') }).Count -and (Test-Path -LiteralPath (Join-Path $Root $entry.Path))) { $manifest.Files += $entry }
        }
    }
    return $manifest
}
function Copy-UpgradeFileAtomic([string]$Source,[string]$Destination) {
    Assert-PlainPath $Source; Assert-PlainPath $Destination
    $directory=[IO.Path]::GetDirectoryName($Destination)
    [IO.Directory]::CreateDirectory($directory) | Out-Null
    # Keep the temporary name independent of long payload names under upgrade backups.
    $temporary=Join-Path $directory ('.wpp-'+[Guid]::NewGuid().ToString('N')+'.tmp')
    try {
        $inputStream=[IO.File]::OpenRead($Source)
        $outputStream=$null
        try {
            $outputStream=[IO.FileStream]::new($temporary,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None,4096,[IO.FileOptions]::WriteThrough)
            $inputStream.CopyTo($outputStream); $outputStream.Flush($true)
        } finally { if ($null -ne $outputStream) { $outputStream.Dispose() }; $inputStream.Dispose() }
        if ((Get-FileHash -LiteralPath $temporary -Algorithm SHA256).Hash -cne (Get-FileHash -LiteralPath $Source -Algorithm SHA256).Hash) { throw '升级文件复制校验失败' }
        for ($attempt=0;$attempt -lt 8;$attempt++) {
            try {
                if (Test-Path -LiteralPath $Destination) { [IO.File]::Replace($temporary,$Destination,[NullString]::Value) }
                else { [IO.File]::Move($temporary,$Destination) }
                break
            } catch {
                $failure=$_.Exception
                while ($null -ne $failure.InnerException) { $failure=$failure.InnerException }
                $sharingViolation=$failure.HResult -in @(0x80070020,0x80070021)
                # Sharing/lock violations are transient. Never delete the valid destination to retry.
                if ($failure -is [IO.IOException] -and $sharingViolation -and $attempt -lt 7 -and (Test-Path -LiteralPath $temporary)) {
                    Start-Sleep -Milliseconds (50*($attempt+1)); continue
                }
                throw [IO.IOException]::new(('升级原子替换失败: '+$Source+' -> '+$Destination+'；HResult=0x'+$failure.HResult.ToString('X8')+'；'+$failure.Message),$failure)
            }
        }
    } finally { if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force } }
}
function Restore-UpgradeTaskState($Manifest,$TaskState,[bool]$WasEnabled,[bool]$WasRunning,[bool]$HadStopRequest) {
    if ($null -eq $TaskState) { return }
    $task=Get-OwnedTask $Manifest
    if ($null -eq $task) { throw '回滚时原任务已消失；文件已恢复，但需修复任务' }
    # Restore the old running state without changing the restored configuration's Paused/Direct intent.
    # Starting a task can require temporary enabling even when logon was originally disabled.
    if ($WasEnabled -or ($WasRunning -and -not $HadStopRequest)) { Enable-ScheduledTask -TaskName $Manifest.TaskName -TaskPath '\' -ErrorAction Stop | Out-Null }
    if ($WasRunning -and -not $HadStopRequest) { Start-ScheduledTask -TaskName $Manifest.TaskName -TaskPath '\' -ErrorAction Stop | Out-Null }
    if (-not $WasEnabled) { Disable-ScheduledTask -TaskName $Manifest.TaskName -TaskPath '\' -ErrorAction Stop | Out-Null }
}
function Install-ProductUpgrade([string]$Source,[string]$Root,$Previous) {
    $recoveryPath=Join-Path $Root 'state/upgrade-recovery.json'; Assert-PlainPath $recoveryPath
    if (Test-Path -LiteralPath $recoveryPath) { throw ('上次升级有未完成的恢复记录；为保护旧配置和备份，请先检查 '+$recoveryPath) }
    $stage=$Root+'.upgrade.'+[Guid]::NewGuid().ToString('N')
    Assert-PlainPath $stage
    $gate=$null; $taken=$false
    try {
        # A source copy/verification failure happens before the existing watcher or files are touched.
        [IO.Directory]::CreateDirectory($stage) | Out-Null; Protect-InstallDirectory $stage
        foreach ($name in Get-DistributionFiles) { Copy-UpgradeFileAtomic (Join-Path $Source $name) (Join-Path $stage $name) }
        $configPath=Join-Path $Root 'config.json'; $gate=New-ConfigurationMutex $configPath
        $taken=Enter-Mutex $gate 5000; if (-not $taken) { throw '配置正在保存；尚未停止后台或替换文件，请稍后升级' }
        $migrated=Read-Configuration $configPath
        Read-OriginalProxy $Root | Out-Null
        # Recheck ownership after staging and acquiring the shared configuration gate.
        foreach ($name in Get-DistributionFiles) {
            if ((Test-Path -LiteralPath (Join-Path $Root $name)) -and -not @($Previous.Files | Where-Object { $_.Path.Replace('\','/') -ceq $name }).Count) { throw ('新版本路径被非本工具文件占用，拒绝覆盖: '+$name) }
        }
        Write-JsonAtomic (Join-Path $stage 'config.json') $migrated
        $manifest=New-InstallManifest $Root $stage $Previous -InPlace:([string]::Equals($Source,$Root,[StringComparison]::OrdinalIgnoreCase))
        Assert-InstallManifest $manifest
        $task=Get-OwnedTask $Previous; $wasEnabled=$false; $wasRunning=$false
        if ($null -ne $task) {
            $wasRunning=([string](Get-TaskField $task 'State')) -in @('Running','Queued')
            $enabled=Get-TaskField (Get-TaskField $task 'Settings') 'Enabled'
            if ($null -ne $enabled) { $wasEnabled=[bool]$enabled } else { $wasEnabled=([string](Get-TaskField $task 'State')) -ne 'Disabled' }
        }
        $backupDir=Join-Path $Root ('user-backups/upgrade-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+[Guid]::NewGuid().ToString('N'))
        Assert-PlainPath $backupDir; [IO.Directory]::CreateDirectory($backupDir) | Out-Null
        $snapshots=@{}
        foreach ($name in @(@(Get-DistributionFiles)+@('config.json.previous','state/installation.json','state/stop.request') | Select-Object -Unique)) {
            $path=Join-Path $Root $name; Assert-PlainPath $path
            $exists=Test-Path -LiteralPath $path
            $snapshots[$name]=[pscustomobject]@{Exists=$exists;Path=$name;Hash=''}
            if ($exists) {
                $backup=Join-Path $backupDir $name; Copy-UpgradeFileAtomic $path $backup
                $snapshots[$name].Hash=(Get-FileHash -LiteralPath $backup -Algorithm SHA256).Hash
            }
        }
        $hadStop=$snapshots['state/stop.request'].Exists
        $record=[ordered]@{Phase='Prepared';Root=$Root;BackupDirectory=$backupDir;OriginalIntent=$migrated.ManagementIntent;TaskEnabled=$wasEnabled;TaskRunning=$wasRunning;Files=@($snapshots.Values)}
        Write-JsonAtomic $recoveryPath $record
        $written=[Collections.Generic.List[string]]::new()
        try {
            Stop-OwnedWatcher $Previous
            foreach ($name in Get-DistributionFiles) {
                if ($name -eq 'config.json') { continue }
                $written.Add($name)
                Copy-UpgradeFileAtomic (Join-Path $stage $name) (Join-Path $Root $name)
            }
            $written.Add('config.json'); $written.Add('config.json.previous')
            Write-JsonAtomic $configPath $migrated ($configPath+'.previous')
            $written.Add('state/installation.json')
            Write-JsonAtomic (Join-Path $Root 'state/installation.json') $manifest
            Remove-Item -LiteralPath $recoveryPath -Force
            return $manifest
        } catch {
            $failure=$_.Exception.Message; $rollbackErrors=[Collections.Generic.List[string]]::new()
            # Restore exact original bytes, including the previous config and ownership manifest.
            for ($index=$written.Count-1; $index -ge 0; $index--) {
                $name=$written[$index]; $path=Join-Path $Root $name
                try {
                    if ($snapshots[$name].Exists) { Copy-UpgradeFileAtomic (Join-Path $backupDir $name) $path }
                    elseif (Test-Path -LiteralPath $path) { Assert-PlainPath $path; Remove-Item -LiteralPath $path -Force }
                } catch { $rollbackErrors.Add($name+': '+$_.Exception.Message) }
            }
            if ($rollbackErrors.Count -eq 0) {
                try {
                    $stop=Join-Path $Root 'state/stop.request'
                    if ($hadStop) { Copy-UpgradeFileAtomic (Join-Path $backupDir 'state/stop.request') $stop }
                    elseif (Test-Path -LiteralPath $stop) { Assert-PlainPath $stop; Remove-Item -LiteralPath $stop -Force }
                } catch { $rollbackErrors.Add('stop.request: '+$_.Exception.Message) }
            }
            # A restarted watcher must be able to acquire its config gate. Its old intent is untouched.
            $gate.ReleaseMutex(); $taken=$false
            if ($rollbackErrors.Count -eq 0) {
                try { Restore-UpgradeTaskState $Previous $task $wasEnabled $wasRunning $hadStop }
                catch { $rollbackErrors.Add('任务状态: '+$_.Exception.Message) }
            }
            if ($rollbackErrors.Count -eq 0) {
                try { Remove-Item -LiteralPath $recoveryPath -Force }
                catch { $rollbackErrors.Add('恢复记录: '+$_.Exception.Message) }
            }
            if ($rollbackErrors.Count -gt 0) {
                # Keep the backup and stop marker. Never start a mixed or incompletely restored installation.
                [IO.File]::WriteAllText((Join-Path $Root 'state/stop.request'),'upgrade rollback incomplete')
                $record.Phase='RollbackFailed'; $record['Failure']=$failure; $record['RollbackErrors']=$rollbackErrors.ToArray()
                try { Write-JsonAtomic $recoveryPath $record } catch { Write-ControlFailure 'UpgradeRollback' $_.Exception.Message }
                throw ('升级失败，回滚尚未完成；已保留停止保护、全部备份和恢复记录 '+$recoveryPath+'。原错误: '+$failure+'；'+($rollbackErrors -join '；'))
            }
            throw ('升级失败，原文件、配置、安装记录及任务状态已回滚；最初代理备份未修改。备份: '+$backupDir+'。原错误: '+$failure)
        }
    } finally {
        if ($taken) { $gate.ReleaseMutex() }; if ($null -ne $gate) { $gate.Dispose() }
        # Only our freshly-created sibling staging directory may be recursively removed.
        $stageFull=[IO.Path]::GetFullPath($stage); $expected=[IO.Path]::GetFullPath($Root)+'.upgrade.'
        if (-not $stageFull.StartsWith($expected,[StringComparison]::OrdinalIgnoreCase) -or $stageFull.Substring($expected.Length) -notmatch '^[0-9a-f]{32}$') { throw '升级暂存路径异常，拒绝清理' }
        Assert-PlainPath $stageFull
        try { if (Test-Path -LiteralPath $stageFull) { Remove-Item -LiteralPath $stageFull -Recurse -Force } }
        catch { Write-ControlFailure 'UpgradeStageCleanup' ('暂存目录保留，安装/回滚结果不受影响: '+$stageFull+'；'+$_.Exception.Message) }
    }
}
function Install-ProductFiles([string]$Source,[string]$Root,$Previous,[string]$SetupConfigPath='') {
    if ($null -ne $Previous -and $null -ne $Previous.PSObject.Properties['Phase'] -and $Previous.Phase -eq 'Uninstalling') { throw '上次卸载尚未完成，请先从完整项目包运行 Uninstall.bat -InstallDir 指定此目录' }
    # Complete source and config preflight happens before stopping an existing monitor or touching its files.
    foreach ($name in Get-DistributionFiles) {
        $p=Join-Path $Source $name
        if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { throw ('安装包文件缺失: '+$name) }
        Assert-PlainPath $p
    }
    $configPath=Join-Path $Source 'config.json'; if ($null -ne $Previous) { $configPath=Join-Path $Root 'config.json' }
    if ($SetupConfigPath) {
        if ($null -ne $Previous) { throw '升级必须保留实际安装配置，不能用首次设置草稿覆盖' }
        Assert-PlainPath $SetupConfigPath; $configPath=$SetupConfigPath
    }
    $validatedConfig=Read-Configuration $configPath
    if ($SetupConfigPath -and -not $validatedConfig.SetupComplete) { throw '首次设置草稿尚未确认，拒绝开启后台组件' }
    foreach ($name in Get-DistributionFiles) { Assert-PlainPath (Join-Path $Root $name) }
    if ($null -ne $Previous) {
        Read-OriginalProxy $Root | Out-Null
        foreach ($name in Get-DistributionFiles) {
            if ((Test-Path -LiteralPath (Join-Path $Root $name)) -and -not @($Previous.Files | Where-Object { $_.Path.Replace('\','/') -ceq $name }).Count) { throw ('新版本路径被非本工具文件占用，拒绝覆盖: '+$name) }
        }
    }
    $prospective=[pscustomobject]@{Root=$Root;OwnerSid=(Get-UserSid);TaskName=($script:TaskPrefix+(Get-UserSid))}
    Get-OwnedTask $prospective | Out-Null
    Assert-ProxyPolicy
    if ($null -ne $Previous) {
        if (-not (Test-Path -LiteralPath (Join-Path $Root 'state/proxy-before-install.json'))) { throw '原配置备份丢失，拒绝更新安装' }
        return Install-ProductUpgrade $Source $Root $Previous
    }
    # Stage the complete first installation beside the target; a copy failure cannot strand a half-install there.
    $stage=$Root+'.stage.'+[Guid]::NewGuid().ToString('N')
    try {
        [IO.Directory]::CreateDirectory($stage) | Out-Null; Protect-InstallDirectory $stage
        Copy-ProductPayload $Source $stage
        Write-JsonAtomic (Join-Path $stage 'config.json') $validatedConfig
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
    foreach ($name in @('last-applied.json','proxy-before-install.json','status.json','control-status.json','check.request','stop.request','pause.request','config-last-good.json','installation.json')) {
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
    if (Test-Path -LiteralPath (Join-Path $Manifest.Root 'state/upgrade-recovery.json')) { throw '升级恢复尚未完成，拒绝启动可能混合版本的后台；请检查升级恢复记录和保留的备份' }
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
    if (-not (Test-RestoreAllowed $current $last -Force:$Force)) { $conflict=[InvalidOperationException]::new('检测到工具最后一次写入之后的代理变更或未完成写入。已停止监控；为保护后续修改，未恢复/删除安装。确认后使用 -ForceRestore；卸载也可用 -KeepCurrentProxy 保留当前配置'); $conflict.Data['WiFiProxyCode']='RestoreConflict'; throw $conflict }
    Restore-ManualSnapshot $original
    Write-Output '已恢复安装前手动代理配置；PAC/自动检测保持当前设置'
}
function Set-OwnedDirectMode($Manifest) {
    $path=Join-Path $Manifest.Root 'config.json'; Assert-PlainPath $path
    $gate=New-ConfigurationMutex $path; $taken=$false
    try {
        $taken=Enter-Mutex $gate 5000; if (-not $taken) { throw '配置正在保存，请稍后重试' }
        $c=Read-Configuration $path
        if (-not $c.SetupComplete) { throw '请先完成首次设置' }
        # Persist before the one-time write, under the same gate the watcher holds before applying.
        $c.ManagementIntent='Direct'; Write-JsonAtomic $path $c ($path+'.previous')
        $applied=Set-TargetProxy ([pscustomobject]@{Action='Disable';Server=''})
        if ($applied.Changed) { Write-JsonAtomic (Join-Path $Manifest.Root 'state/last-applied.json') $applied.Snapshot }
        Write-Output '已恢复直连并暂停自动切换；仅关闭 Windows 手动代理，安装前备份和 PAC/自动检测保持不变'
    } finally { if ($taken) { $gate.ReleaseMutex() }; $gate.Dispose() }
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

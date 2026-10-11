# Loaded by Run-Tests.ps1. These tests never mutate real registry, tasks or proxy.
. (Join-Path $root 'lib/Desktop.ps1')
Case 'V3 立即检测请求能打断长轮询且不改变网络规则' {
    $clock=[Diagnostics.Stopwatch]::StartNew()
    $woke=Wait-MonitorSignal 300000 $null { $false } { $true }
    Check ($woke -and $clock.ElapsedMilliseconds -lt 1000)
    Check ((Get-Target (Snapshot (Link 'MC-Office')) $config).Action -eq 'Disable')
}
Case 'V3 BAT 已移动到 tools，全部入口与原控制脚本正确关联' {
    foreach ($name in @('Install','Start','Stop','Uninstall','RestoreProxy','Status','Diagnose')) {
        $p=Join-Path $root ('tools/'+$name+'.bat'); Check (Test-Path -LiteralPath $p)
        $text=Get-Content -LiteralPath $p -Raw
        Check ($text.Contains('DisableDelayedExpansion') -and ($text.Contains('"%~dp0..\Control.ps1"') -or $text.Contains('"%~dp0..\Diagnose.ps1"')))
    }
}
Case 'V3 旧安装根目录 BAT 归属在升级后保留，卸载仍能清理' {
    New-LifeFixture; . $lifeMocks
    try {
        $m=Install-ProductFiles $script:life.Source $script:life.Root $null
        $legacy=Join-Path $script:life.Root 'Install.bat'; [IO.File]::WriteAllText($legacy,'old owned bat')
        $m.Files += [pscustomobject]@{Path='Install.bat';Hash=(Get-FileHash -LiteralPath $legacy -Algorithm SHA256).Hash}
        $updated=Install-ProductFiles $script:life.Source $script:life.Root $m
        Check (@($updated.Files | Where-Object {$_.Path -ceq 'Install.bat'}).Count -eq 1)
        Assert-InstallManifest $updated; Uninstall-Product $updated | Out-Null
        Check (-not (Test-Path -LiteralPath $legacy))
    } finally { Remove-Item -LiteralPath $script:life.Base -Recurse -Force }
}
Case 'V3 恢复冲突提供机器可读错误代码而非依赖中文文本匹配' {
    New-LifeFixture
    function Get-ManualSnapshot { Registry-Snapshot $true 'changed:1234' }
    try {
        [IO.Directory]::CreateDirectory((Join-Path $script:life.Root 'state')) | Out-Null
        Write-JsonAtomic (Join-Path $script:life.Root 'state/proxy-before-install.json') (Registry-Snapshot $false 'original:80')
        Write-JsonAtomic (Join-Path $script:life.Root 'state/last-applied.json') (Registry-Snapshot $true 'last:7890')
        $code=''; try { Restore-OwnedProxy ([pscustomobject]@{Root=$script:life.Root}) } catch { $code=$_.Exception.Data['WiFiProxyCode'] }
        Check ($code -ceq 'RestoreConflict')
    } finally { Remove-Item -LiteralPath $script:life.Base -Recurse -Force }
}
Case 'V3 桌面清单拒绝跨用户、越界文件与无效哈希' {
    New-LifeFixture
    function Get-UserSid { 'S-1-5-21-1-2-3-1001' }
    try {
        $path=Join-Path $script:life.Root 'app/desktop.json'; [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path)) | Out-Null
        $m=[pscustomobject]@{Product='WiFiProxySwitcher-Desktop-v3';OwnerSid=(Get-UserSid);Root=$script:life.Root;Current='app/3.0.0-AAAAAAAAAAAA/WiFiProxySwitcher.exe';Files=@([pscustomobject]@{Path='app/3.0.0-AAAAAAAAAAAA/WiFiProxySwitcher.exe';Hash=('A'*64)})}
        Write-JsonAtomic $path $m; Check ($null -ne (Read-DesktopInstall $script:life.Root))
        foreach ($bad in @('../outside.exe','app/other.exe','C:/outside.exe')) {
            $m.Files[0].Path=$bad; Write-JsonAtomic $path $m; $caught=$false
            try { Read-DesktopInstall $script:life.Root | Out-Null } catch { $caught=$true }; Check $caught
        }
        $m.Files[0].Path=$m.Current; $m.OwnerSid='OTHER'; Write-JsonAtomic $path $m; $caught=$false
        try { Read-DesktopInstall $script:life.Root | Out-Null } catch { $caught=$true }; Check $caught
    } finally { Remove-Item -LiteralPath $script:life.Base -Recurse -Force }
}
Case 'V3 桌面安装采用版本哈希路径，不覆盖正在运行的旧 EXE' {
    $text=Get-Content -LiteralPath (Join-Path $root 'lib/Desktop.ps1') -Raw
    Check ($text.Contains("'app/3.0.0-'") -and $text.Contains('Get-FileHash') -and $text.Contains('Assert-DesktopRegistration'))
    $control=Get-Content -LiteralPath (Join-Path $root 'Control.ps1') -Raw
    Check ($control.Contains('$result.Code') -and $control.Contains('RestoreConflict') -and $control.Contains('-LogonType Interactive -RunLevel Limited'))
}

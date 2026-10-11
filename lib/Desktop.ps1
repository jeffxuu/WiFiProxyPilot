Set-StrictMode -Version 2.0
$script:DesktopUninstallKey='Software\Microsoft\Windows\CurrentVersion\Uninstall\WiFiProxySwitcher'
function Read-DesktopInstall([string]$Root) {
    $path=Join-Path $Root 'app/desktop.json'; Assert-PlainPath $path
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    $m=Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($m.Product -cne 'WiFiProxySwitcher-Desktop-v3' -or $m.OwnerSid -cne (Get-UserSid) -or -not [string]::Equals($m.Root,$Root,[StringComparison]::OrdinalIgnoreCase)) { throw '桌面安装记录不属于当前用户/目录' }
    foreach ($f in $m.Files) {
        if ($f.Path -cnotmatch '^app/[0-9]+\.[0-9]+\.[0-9]+-[A-F0-9]{12}/WiFiProxySwitcher\.exe$' -or $f.Hash -cnotmatch '^[A-F0-9]{64}$') { throw '桌面文件清单无效，拒绝清理' }
        Assert-PlainPath (Join-Path $Root $f.Path)
    }
    if (-not @($m.Files | Where-Object {$_.Path -ceq $m.Current}).Count) { throw '桌面当前版本不在清单中' }
    return $m
}
function Get-DesktopShortcut { return Join-Path ([Environment]::GetFolderPath('Programs')) 'WiFiProxySwitcher.lnk' }
function Assert-DesktopRegistration([string]$Root,$Manifest) {
    $key=[Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($script:DesktopUninstallKey)
    if ($null -ne $key) {
        try { if ($key.GetValue('OwnerSid','') -cne (Get-UserSid) -or -not [string]::Equals($key.GetValue('InstallLocation',''),$Root,[StringComparison]::OrdinalIgnoreCase)) { throw '同名卸载项不属于当前安装，拒绝覆盖' } } finally { $key.Dispose() }
    }
    $shortcut=Get-DesktopShortcut; Assert-PlainPath $shortcut
    if (Test-Path -LiteralPath $shortcut) {
        if ($null -eq $Manifest) { throw '同名开始菜单入口已存在且没有归属记录，拒绝覆盖' }
        $shell=New-Object -ComObject WScript.Shell
        try {
            $link=$shell.CreateShortcut($shortcut)
            try { if (-not @($Manifest.Files | Where-Object { [string]::Equals((Join-Path $Root $_.Path),$link.TargetPath,[StringComparison]::OrdinalIgnoreCase) }).Count) { throw '开始菜单入口已被其他程序修改，拒绝覆盖' } }
            finally { [Runtime.InteropServices.Marshal]::FinalReleaseComObject($link) | Out-Null }
        } finally { [Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell) | Out-Null }
    }
}
function Install-DesktopFiles([string]$Root,[string]$SourceExe) {
    Assert-PlainPath $SourceExe
    if (-not (Test-Path -LiteralPath $SourceExe -PathType Leaf) -or [IO.Path]::GetExtension($SourceExe) -ine '.exe') { throw '桌面 EXE 文件不存在' }
    $old=Read-DesktopInstall $Root; Assert-DesktopRegistration $Root $old
    $hash=(Get-FileHash -LiteralPath $SourceExe -Algorithm SHA256).Hash.ToUpperInvariant()
    $rel='app/3.0.0-'+$hash.Substring(0,12)+'/WiFiProxySwitcher.exe'; $dest=Join-Path $Root $rel
    Assert-PlainPath $dest
    if (Test-Path -LiteralPath $dest) {
        if ((Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash -cne $hash) { throw '版本目录已被其他文件占用，拒绝覆盖' }
    } else {
        [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($dest)) | Out-Null
        $stage=$dest+'.tmp'; Assert-PlainPath $stage
        try { Copy-Item -LiteralPath $SourceExe -Destination $stage -Force; if ((Get-FileHash -LiteralPath $stage -Algorithm SHA256).Hash -cne $hash) { throw 'EXE 复制校验失败' }; Move-Item -LiteralPath $stage -Destination $dest }
        finally { if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Force } }
    }
    $files=@(); if ($null -ne $old) { $files=@($old.Files) }
    if (-not @($files | Where-Object {$_.Path -ceq $rel}).Count) { $files += [pscustomobject]@{Path=$rel;Hash=$hash} }
    $m=[pscustomobject]@{Product='WiFiProxySwitcher-Desktop-v3';OwnerSid=(Get-UserSid);Root=$Root;Current=$rel;Files=$files}
    Write-JsonAtomic (Join-Path $Root 'app/desktop.json') $m
    $key=[Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($script:DesktopUninstallKey)
    try {
        foreach ($pair in @(@('DisplayName','Wi-Fi 智能代理切换'),@('DisplayVersion','3.0.0'),@('Publisher','WiFiProxySwitcher'),@('OwnerSid',(Get-UserSid)),@('InstallLocation',$Root),@('DisplayIcon',$dest),@('UninstallString',('"'+$dest+'" /uninstall')), @('QuietUninstallString',('"'+$dest+'" /uninstall /quiet')))) { $key.SetValue($pair[0],$pair[1],[Microsoft.Win32.RegistryValueKind]::String) }
        $key.SetValue('NoModify',1,[Microsoft.Win32.RegistryValueKind]::DWord); $key.SetValue('NoRepair',1,[Microsoft.Win32.RegistryValueKind]::DWord)
    } finally { $key.Dispose() }
    $shortcut=Get-DesktopShortcut; [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($shortcut)) | Out-Null
    $shell=New-Object -ComObject WScript.Shell
    try { $link=$shell.CreateShortcut($shortcut); try { $link.TargetPath=$dest; $link.WorkingDirectory=[IO.Path]::GetDirectoryName($dest); $link.Description='Wi-Fi 智能代理切换'; $link.Save() } finally { [Runtime.InteropServices.Marshal]::FinalReleaseComObject($link) | Out-Null } }
    finally { [Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell) | Out-Null }
    return $m
}
function Remove-DesktopFiles($Manifest) {
    if ($null -eq $Manifest) { return }
    $root=$Manifest.Root
    $checked=Read-DesktopInstall $root; if ($null -eq $checked) { return }
    Assert-DesktopRegistration $root $checked
    # Only remove hash-matching manifest entries. Keep marker/registration on a locked-file failure for retry.
    foreach ($f in $checked.Files) {
        $path=Join-Path $root $f.Path
        if (Test-Path -LiteralPath $path) {
            if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -cne $f.Hash) { throw '桌面文件被修改，保留文件与清单，请检查后重试' }
            Remove-Item -LiteralPath $path -Force
        }
    }
    $shortcut=Get-DesktopShortcut; if (Test-Path -LiteralPath $shortcut) { Remove-Item -LiteralPath $shortcut -Force }
    [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree($script:DesktopUninstallKey,$false)
    Remove-Item -LiteralPath (Join-Path $root 'app/desktop.json') -Force
}

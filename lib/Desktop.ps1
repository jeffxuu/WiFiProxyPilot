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
    $rel='app/3.3.0-'+$hash.Substring(0,12)+'/WiFiProxySwitcher.exe'; $dest=Join-Path $Root $rel
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
    Register-DesktopEntries $Root $dest
    return $m
}
function Register-DesktopEntries([string]$Root,[string]$dest) {
    $key=[Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($script:DesktopUninstallKey)
    try {
        foreach ($pair in @(@('DisplayName','WiFi Proxy Pilot'),@('DisplayVersion','3.3.0-beta.1'),@('Publisher','WiFi Proxy Pilot contributors'),@('OwnerSid',(Get-UserSid)),@('InstallLocation',$Root),@('DisplayIcon',$dest),@('UninstallString',('"'+$dest+'" /uninstall')), @('QuietUninstallString',('"'+$dest+'" /uninstall /quiet')))) { $key.SetValue($pair[0],$pair[1],[Microsoft.Win32.RegistryValueKind]::String) }
        $key.SetValue('NoModify',1,[Microsoft.Win32.RegistryValueKind]::DWord); $key.SetValue('NoRepair',1,[Microsoft.Win32.RegistryValueKind]::DWord)
    } finally { $key.Dispose() }
    $shortcut=Get-DesktopShortcut; [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($shortcut)) | Out-Null
    $shell=New-Object -ComObject WScript.Shell
    try { $link=$shell.CreateShortcut($shortcut); try { $link.TargetPath=$dest; $link.WorkingDirectory=[IO.Path]::GetDirectoryName($dest); $link.Description='WiFi Proxy Pilot — Wi-Fi 智能代理助手'; $link.Save() } finally { [Runtime.InteropServices.Marshal]::FinalReleaseComObject($link) | Out-Null } }
    finally { [Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell) | Out-Null }
}
function Remove-DesktopFiles($Manifest) {
    if ($null -eq $Manifest) { return }
    $root=$Manifest.Root
    $checked=Read-DesktopInstall $root; if ($null -eq $checked) { return }
    Assert-DesktopRegistration $root $checked
    Set-TrayLoginEntry $root $checked $false
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

function Open-TrayLoginRegistry { return [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey('Software\Microsoft\Windows\CurrentVersion\Run') }
function Set-TrayLoginEntry([string]$Root,$Manifest,[bool]$Enabled) {
    if ($null -eq $Manifest) { if ($Enabled) { throw '桌面安装记录缺失，请修复安装' }; return }
    $key=Open-TrayLoginRegistry
    try {
        $name='WiFiProxySwitcher.Tray'; $value=[string]$key.GetValue($name,'')
        $owned=@($Manifest.Files | ForEach-Object { '"'+(Join-Path $Root $_.Path)+'" /tray' })
        if ($value -and $value -cnotin $owned) { throw '同名托盘自启项已被其他程序修改，拒绝覆盖或删除' }
        if ($Enabled) { $key.SetValue($name,('"'+(Join-Path $Root $Manifest.Current)+'" /tray'),[Microsoft.Win32.RegistryValueKind]::String) }
        else { $key.DeleteValue($name,$false) }
    } finally { $key.Dispose() }
}
function Apply-LoginSettings([string]$Root,$Manifest) {
    $c=Read-Configuration (Join-Path $Root 'config.json')
    $enabled=$true; if ($null -ne $c.PSObject.Properties['LoginMonitor']) { $enabled=$c.LoginMonitor }
    $task=Get-OwnedTask $Manifest
    if ($null -eq $task) { throw '监控登录任务缺失，请修复安装' }
    if ($enabled) { Enable-ScheduledTask -TaskName $Manifest.TaskName -TaskPath '\' -ErrorAction Stop | Out-Null }
    else { Disable-ScheduledTask -TaskName $Manifest.TaskName -TaskPath '\' -ErrorAction Stop | Out-Null }
    $tray=$true; if ($null -ne $c.PSObject.Properties['TrayAutoStart']) { $tray=$c.TrayAutoStart }
    $installer=Read-InstallerDesktop
    if ($null -ne $installer) { Set-InstallerTrayLogin $installer $tray }
    else { $desktop=Read-DesktopInstall $Root; if ($null -ne $desktop) { Set-TrayLoginEntry $Root $desktop $tray } }
}

# Inno Setup is the sole owner of program files, shortcuts and Apps registration.
# Engine data/backup/task ownership continues using the original v1 installation root.
function Read-InstallerDesktop {
    $key=[Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Software\WiFiProxySwitcher')
    try {
        if ($null -eq $key -or $key.GetValue('DesktopOwner','') -cne 'Inno') { return $null }
        $directory=[string]$key.GetValue('DesktopAppDir','')
    } finally { if ($null -ne $key) { $key.Dispose() } }
    Assert-InstallerDesktopDirectory $directory
}
function Assert-InstallerDesktopDirectory([string]$Directory) {
    if (-not [IO.Path]::IsPathRooted($Directory) -or $Directory.StartsWith('\\')) { throw 'Installer app directory is invalid' }
    $directory=[IO.Path]::GetFullPath($Directory).TrimEnd('\')
    Assert-PlainPath $directory
    $path=Join-Path $directory 'installer-owned.json'; Assert-PlainPath $path
    $owner=Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($owner.Product -cne 'WiFiProxyPilot-Inno-v1' -or $owner.OwnerSid -cne (Get-UserSid) -or $owner.AppId -cne '{15F7908C-5C54-4D45-9343-1973BFEA3B47}' -or -not [string]::Equals($owner.AppDir,$directory,[StringComparison]::OrdinalIgnoreCase)) { throw 'Installer ownership record does not match this user/directory' }
    $exe=Join-Path $directory 'WiFiProxyPilot.exe'; Assert-PlainPath $exe
    if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { throw 'Installed application is missing; repair Setup before enabling tray startup' }
    Assert-InstallerApplicationFiles $owner | Out-Null
    return $owner
}
function Assert-InstallerApplicationFiles($Owner) {
    $directory=[IO.Path]::GetFullPath($Owner.AppDir).TrimEnd('\')
    $receiptPath=Join-Path $directory 'installer-files.json'; Assert-PlainPath $receiptPath
    if ($null -eq $Owner.PSObject.Properties['ReceiptSha256'] -or $Owner.ReceiptSha256 -cnotmatch '^[A-F0-9]{64}$' -or (Get-FileHash -LiteralPath $receiptPath -Algorithm SHA256).Hash -cne $Owner.ReceiptSha256) { Throw-ProductError 'InstallerAppModified' 'Installed file receipt changed or is missing; program files were preserved. Review or repair the installation.' }
    $receipt=Get-Content -LiteralPath $receiptPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $known=@{}
    foreach ($file in $receipt.Files) {
        if ($file.Path -match '(^|/)\.\.?(/|$)' -or $file.Path -match '[:\\\r\n]' -or $file.Path.StartsWith('/') -or $file.Hash -cnotmatch '^[A-F0-9]{64}$' -or $known.ContainsKey($file.Path)) { Throw-ProductError 'InstallerAppModified' 'Installed file receipt contains an invalid path or hash' }
        $path=Join-Path $directory $file.Path; Assert-PlainPath $path
        if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -cne $file.Hash) { Throw-ProductError 'InstallerAppModified' ('An installed program file changed or is missing; preserving files and refusing execution: '+$file.Path) }
        $known[$file.Path]=$file.Hash
    }
    if (-not $known.ContainsKey('WiFiProxyPilot.exe')) { Throw-ProductError 'InstallerAppModified' 'Installed file receipt does not own the application executable' }
    $uninstaller=Join-Path $directory 'unins000.exe'; Assert-PlainPath $uninstaller
    if ($null -eq $Owner.PSObject.Properties['UninstallerSha256'] -or $Owner.UninstallerSha256 -cnotmatch '^[A-F0-9]{64}$' -or -not (Test-Path -LiteralPath $uninstaller -PathType Leaf) -or (Get-FileHash -LiteralPath $uninstaller -Algorithm SHA256).Hash -cne $Owner.UninstallerSha256) { Throw-ProductError 'InstallerAppModified' 'Uninstaller changed or is missing; refusing to launch or remove unverified program files' }
    return $known
}
function Set-InstallerTrayLogin($Owner,[bool]$Enabled) {
    $checked=Assert-InstallerDesktopDirectory $Owner.AppDir
    $key=Open-TrayLoginRegistry
    try {
        $name='WiFiProxySwitcher.Tray'; $expected='"'+(Join-Path $checked.AppDir 'WiFiProxyPilot.exe')+'" /tray'
        $value=[string]$key.GetValue($name,'')
        if ($value -and $value -cne $expected) { throw 'Tray startup entry has another owner; refusing to overwrite/remove it' }
        if ($Enabled) { $key.SetValue($name,$expected,[Microsoft.Win32.RegistryValueKind]::String) }
        else { $key.DeleteValue($name,$false) }
    } finally { $key.Dispose() }
}

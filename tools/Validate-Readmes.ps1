[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$files=@('README.md','README.zh-CN.md','README.zh-TW.md','README.ja.md','README.ko.md','README.es.md','README.fr.md','README.de.md','README.pt-BR.md','README.ru.md','README.vi.md')
foreach($name in $files){
    $path=Join-Path $root $name
    if(-not (Test-Path -LiteralPath $path -PathType Leaf)){throw ('Missing README: '+$name)}
    $content=[IO.File]::ReadAllText($path)
    if($content.Length -lt 7000){throw ('Incomplete translation: '+$name)}
    foreach($target in $files){if(-not $content.Contains(']('+ $target +')')){throw ('Missing language navigation: '+$name+' -> '+$target)}}
    foreach($m in [regex]::Matches($content,'\]\(([^)]+)\)')){
        $target=$m.Groups[1].Value
        if($target -match '^(https?://|#|mailto:)'){continue}
        $local=($target -split '#')[0]
        if(-not (Test-Path -LiteralPath (Join-Path $root $local))){throw ('Broken local link: '+$name+' -> '+$target)}
    }
    if($content -match 'jeffxuu/WiFi-test'){throw ('Old repository URL: '+$name)}
    if($content -match 'v3\.[01]\b'){throw ('Obsolete version display: '+$name)}
    if($name -in @('README.md','README.zh-CN.md')){
        foreach($asset in @('WiFiProxyPilot-Setup-x64.exe','WiFiProxyPilot-Portable-x64.zip','SHA256.txt')){
            if(-not $content.Contains('releases/download/v3.3.0-beta.1/'+$asset)){throw ('Missing v3.3 asset link: '+$name+' -> '+$asset)}
        }
        if($content.Contains('releases/download/v3.2.0-beta.1/WiFiProxySwitcher.exe')){throw ('Current README still recommends old application EXE: '+$name)}
        $setup=$content.IndexOf('releases/download/v3.3.0-beta.1/WiFiProxyPilot-Setup-x64.exe')
        $portable=$content.IndexOf('releases/download/v3.3.0-beta.1/WiFiProxyPilot-Portable-x64.zip')
        if($setup -ge $portable){throw ('Installer must precede optional portable archive: '+$name)}
    }else{
        if(-not $content.StartsWith('> **Documentation version: v3.2.0-beta.1.**')){throw ('Translated README must identify its older documentation version: '+$name)}
        if(-not $content.Contains('releases/download/v3.3.0-beta.1/WiFiProxyPilot-Setup-x64.exe')){throw ('Translated README is missing current Setup notice: '+$name)}
        foreach($asset in @('WiFiProxySwitcher.exe','WiFiProxySwitcher.zip','SHA256.txt')){
            if(-not $content.Contains('releases/download/v3.2.0-beta.1/'+$asset)){throw ('Missing documented v3.2 asset link: '+$name+' -> '+$asset)}
        }
    }
    if(-not $content.Contains('repos=jeffxuu/WiFiProxyPilot')){throw ('Missing repository Star History: '+$name)}
}
Write-Output ('Verified '+$files.Count+' complete README files, language navigation, current Setup-first assets, older translation notices and relative links/images.')

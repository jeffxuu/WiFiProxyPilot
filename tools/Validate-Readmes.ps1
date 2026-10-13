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
    foreach($asset in @('WiFiProxySwitcher.exe','WiFiProxySwitcher.zip','SHA256.txt')){
        if(-not $content.Contains('releases/download/v3.2.0-beta.1/'+$asset)){throw ('Missing v3.2 asset link: '+$name+' -> '+$asset)}
    }
    if(-not $content.Contains('repos=jeffxuu/WiFiProxyPilot')){throw ('Missing repository Star History: '+$name)}
}
Write-Output ('Verified '+$files.Count+' complete README files, language navigation and relative links/images.')

#requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$Exe,[string]$OutputDirectory='', [ValidateRange(1,20)][int]$Runs=4)
$ErrorActionPreference='Stop'
$Exe=[IO.Path]::GetFullPath($Exe)
if (-not $OutputDirectory) { $OutputDirectory=Join-Path (Split-Path $PSScriptRoot -Parent) ('artifacts/performance-'+[Guid]::NewGuid().ToString('N')) }
$OutputDirectory=[IO.Path]::GetFullPath($OutputDirectory); [IO.Directory]::CreateDirectory($OutputDirectory) | Out-Null
$originalBundle=$env:DOTNET_BUNDLE_EXTRACT_BASE_DIR; $rows=@()
$assemblies=@(foreach($assembly in @('WiFiProxySwitcher.dll','WiFiProxySwitcher.Core.dll','en-US/WiFiProxySwitcher.resources.dll','zh-CN/WiFiProxySwitcher.resources.dll')) { $assemblyPath=Join-Path ([IO.Path]::GetDirectoryName($Exe)) $assembly; if(Test-Path -LiteralPath $assemblyPath){[pscustomobject]@{Name=$assembly;Sha256=(Get-FileHash -LiteralPath $assemblyPath -Algorithm SHA256).Hash}} })
$metadata=[pscustomobject]@{Time=[DateTimeOffset]::Now.ToString('o');Exe=$Exe;ExeBytes=(Get-Item -LiteralPath $Exe).Length;ExeSha256=(Get-FileHash -LiteralPath $Exe -Algorithm SHA256).Hash;Assemblies=$assemblies;Runtime=$(if($assemblies.Count){'unbundled apphost and self-contained runtime'}else{'single-file self-contained runtime'})}
$metadata | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $OutputDirectory 'metadata.json') -Encoding UTF8
function Read-Measurement([string]$Path) {
    $file=[IO.FileStream]::new($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
    $reader=[IO.StreamReader]::new($file)
    try { return ($reader.ReadToEnd() | ConvertFrom-Json) } finally { $reader.Dispose(); $file.Dispose() }
}
try {
    $env:DOTNET_BUNDLE_EXTRACT_BASE_DIR=Join-Path $OutputDirectory 'new-bundle-cache'
    foreach ($run in 1..$Runs) {
        $dir=Join-Path $OutputDirectory ('run-'+$run); [IO.Directory]::CreateDirectory($dir) | Out-Null
        $report=Join-Path $dir 'startup.json'
        $args=@('/benchmark','/output',('"'+$report+'"'))
        $p=$null; $data=$null; $reopenMs=$null; $cpuPercent=$null; $cpuMs=$null
        try {
            if ($run -gt 1) { Copy-Item -LiteralPath (Join-Path $OutputDirectory 'run-1/fixture') -Destination (Join-Path $dir 'fixture') -Recurse }
            $p=Start-Process -FilePath $Exe -ArgumentList $args -PassThru -WindowStyle Hidden
            $deadline=[Diagnostics.Stopwatch]::StartNew();$data=$null
            do { Start-Sleep -Milliseconds 100; if(Test-Path -LiteralPath $report){try{$data=Read-Measurement $report}catch{}};if($p.HasExited){throw ('EXE exited before benchmark: '+$p.ExitCode)} } while(($null -eq $data -or $null -eq $data.PSObject.Properties['PayloadReady']) -and ($null -eq $data -or $null -eq $data.PSObject.Properties['PayloadFailed']) -and $deadline.Elapsed.TotalSeconds -lt 20)
            if($data -and $data.PSObject.Properties['PayloadFailed']){throw ('Payload preparation failed: '+$data.InitializationError)}; if($null -eq $data -or $null -eq $data.PSObject.Properties['PayloadReady']){throw 'Startup report timeout'}
            $p.Refresh();$cpuBefore=$p.TotalProcessorTime.TotalMilliseconds;$cpuClock=[Diagnostics.Stopwatch]::StartNew();Start-Sleep -Seconds 5;$p.Refresh();$cpuMs=$p.TotalProcessorTime.TotalMilliseconds-$cpuBefore;$cpuPercent=$cpuMs/$cpuClock.Elapsed.TotalMilliseconds/[Environment]::ProcessorCount*100
            $deadline.Restart()
            do { Start-Sleep -Milliseconds 100;$data=Read-Measurement $report } while($null -eq $data.PSObject.Properties['ReadyReopen'] -and $deadline.Elapsed.TotalSeconds -lt 15)
            if($null -eq $data.PSObject.Properties['ReadyReopen']) { throw 'Resident hide was not observed' }
            $reopen=[Diagnostics.Stopwatch]::StartNew();$second=Start-Process -FilePath $Exe -ArgumentList $args -PassThru -WindowStyle Hidden
            try { $deadline.Restart();do{Start-Sleep -Milliseconds 20;$data=Read-Measurement $report}while(($null -eq $data.PSObject.Properties['Reopened'] -or $null -eq $data.PSObject.Properties['TrayPaintMilliseconds']) -and $deadline.Elapsed.TotalSeconds -lt 10);$reopenMs=$reopen.Elapsed.TotalMilliseconds;if(-not $second.WaitForExit(10000)){throw 'Secondary activation exit timeout'};if($second.ExitCode -ne 0){throw 'Secondary activation failed'} } finally { if(-not $second.HasExited){$second.Kill();$second.WaitForExit()};$second.Dispose() }
            foreach($required in @('FirstVisible','FirstPaint','FirstStatus','Reopened','TrayOpenMilliseconds','TrayPaintMilliseconds')) { if($null -eq $data.PSObject.Properties[$required] -or [double]$data.$required -le 0){throw ('Required rendering/status observation missing: '+$required)} }
            if($data.PSObject.Properties['InitializationError']){throw ('Initialization failed: '+$data.InitializationError)}
            $p.Refresh();$rows+=[pscustomobject]@{Run=$run;Succeeded=$true;Error='';Kind=$(if($run -eq 1){'new native extraction directory where applicable + new payload cache (OS cache uncontrolled)'}else{'native runtime + payload cache hit'});FirstVisibleMs=$data.FirstVisible;FirstPaintMs=$data.FirstPaint;FirstStatusMs=$data.FirstStatus;PayloadReadyMs=$data.PayloadReady;ExtractMs=$data.ExtractMs;VerifyMs=$data.VerifyMs;CacheHit=$data.CacheHit;ThemeLoadMs=$data.ThemeLoadMilliseconds;WindowXamlMs=$data.WindowXamlMilliseconds;WindowIconMs=$data.WindowIconMilliseconds;FirstPageMs=$data.FirstPageMilliseconds;TrayOpenMs=$data.TrayOpenMilliseconds;TrayPaintMs=$data.TrayPaintMilliseconds;StatusRefreshMs=$data.StatusRefreshMilliseconds;ReopenViaSecondExeMs=$reopenMs;CpuPercentNormalized=$cpuPercent;CpuMillisecondsIn5Seconds=$cpuMs;WorkingSetMiB=($p.WorkingSet64/1MB);PrivateMiB=($p.PrivateMemorySize64/1MB)}
        } catch {
            $rows+=[pscustomobject]@{Run=$run;Succeeded=$false;Error=$_.Exception.ToString();Kind='failed sample retained';FirstVisibleMs=$data.FirstVisible;FirstPaintMs=$data.FirstPaint;FirstStatusMs=$data.FirstStatus;PayloadReadyMs=$data.PayloadReady;ExtractMs=$data.ExtractMs;VerifyMs=$data.VerifyMs;CacheHit=$data.CacheHit;TrayOpenMs=$data.TrayOpenMilliseconds;TrayPaintMs=$data.TrayPaintMilliseconds;StatusRefreshMs=$data.StatusRefreshMilliseconds;ReopenViaSecondExeMs=$reopenMs;CpuPercentNormalized=$cpuPercent;CpuMillisecondsIn5Seconds=$cpuMs};Write-Warning ('Run '+$run+' failed; evidence retained: '+$_.Exception.Message)
        } finally { $rows | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $OutputDirectory 'samples.json') -Encoding UTF8; if($p){if(-not $p.HasExited){$p.Kill();$p.WaitForExit()};$p.Dispose()} }
    }
} finally { $env:DOTNET_BUNDLE_EXTRACT_BASE_DIR=$originalBundle }
$os=Get-CimInstance Win32_OperatingSystem; $cpu=Get-CimInstance Win32_Processor | Select-Object -First 1
$failed=@($rows | Where-Object { -not $_.Succeeded }).Count
$result=[pscustomobject]@{Time=[DateTimeOffset]::Now.ToString('o');Exe=$Exe;ExeBytes=$metadata.ExeBytes;ExeSha256=$metadata.ExeSha256;Assemblies=$assemblies;Runtime=$metadata.Runtime;OS=$os.Caption;Build=$os.Version;CPU=$cpu.Name;LogicalProcessors=[Environment]::ProcessorCount;RAMGiB=([double]$os.TotalVisibleMemorySize/1MB);Network='isolated fixture, no proxy/tasks/network mutation';Defender='not disabled; influence not independently measured';Cold='fresh native bundle directory where applicable and payload directory; not OS-cold or reboot-cold';FailedSamples=$failed;StartupTargetMilliseconds=1500;ResidentTargetMilliseconds=150;StartupTargetMet=($failed -eq 0 -and @($rows | Where-Object {$_.FirstPaintMs -gt 1500}).Count -eq 0);ResidentTargetMet=($failed -eq 0 -and @($rows | Where-Object {$_.TrayPaintMs -gt 150}).Count -eq 0);Rows=$rows}
$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $OutputDirectory 'results.json') -Encoding UTF8
$rows | Format-Table
if($failed -gt 0){throw ('Performance collection had '+$failed+' failed sample(s); all observations retained.')}

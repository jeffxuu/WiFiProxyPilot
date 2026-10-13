#requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$Exe,[string]$OutputDirectory='', [int]$Runs=4)
$ErrorActionPreference='Stop'
$Exe=[IO.Path]::GetFullPath($Exe)
if (-not $OutputDirectory) { $OutputDirectory=Join-Path (Split-Path $PSScriptRoot -Parent) ('artifacts/performance-'+[Guid]::NewGuid().ToString('N')) }
$OutputDirectory=[IO.Path]::GetFullPath($OutputDirectory); [IO.Directory]::CreateDirectory($OutputDirectory) | Out-Null
$originalBundle=$env:DOTNET_BUNDLE_EXTRACT_BASE_DIR; $rows=@()
try {
    $env:DOTNET_BUNDLE_EXTRACT_BASE_DIR=Join-Path $OutputDirectory 'new-bundle-cache'
    foreach ($run in 1..$Runs) {
        $dir=Join-Path $OutputDirectory ('run-'+$run); [IO.Directory]::CreateDirectory($dir) | Out-Null
        if ($run -gt 1) { Copy-Item -LiteralPath (Join-Path $OutputDirectory 'run-1/fixture') -Destination (Join-Path $dir 'fixture') -Recurse }
        $report=Join-Path $dir 'startup.json'
        $args=@('/benchmark','/output',('"'+$report+'"'))
        $p=Start-Process -FilePath $Exe -ArgumentList $args -PassThru -WindowStyle Hidden
        try {
            $deadline=[Diagnostics.Stopwatch]::StartNew();$data=$null
            do { Start-Sleep -Milliseconds 100; if(Test-Path -LiteralPath $report){try{$data=Get-Content -LiteralPath $report -Raw | ConvertFrom-Json}catch{}};if($p.HasExited){throw ('EXE exited before benchmark: '+$p.ExitCode)} } while(($null -eq $data -or $null -eq $data.PSObject.Properties['PayloadReady']) -and $deadline.Elapsed.TotalSeconds -lt 20)
            if($null -eq $data -or $null -eq $data.PSObject.Properties['PayloadReady']){throw 'Startup report timeout'}
            $p.Refresh();$cpuBefore=$p.TotalProcessorTime.TotalMilliseconds;$cpuClock=[Diagnostics.Stopwatch]::StartNew();Start-Sleep -Seconds 5;$p.Refresh();$cpuMs=$p.TotalProcessorTime.TotalMilliseconds-$cpuBefore;$cpuPercent=$cpuMs/$cpuClock.Elapsed.TotalMilliseconds/[Environment]::ProcessorCount*100
            $deadline.Restart()
            do { Start-Sleep -Milliseconds 100;$data=Get-Content -LiteralPath $report -Raw | ConvertFrom-Json } while($null -eq $data.PSObject.Properties['ReadyReopen'] -and $deadline.Elapsed.TotalSeconds -lt 15)
            $reopen=[Diagnostics.Stopwatch]::StartNew();$second=Start-Process -FilePath $Exe -ArgumentList $args -PassThru -WindowStyle Hidden
            try { $deadline.Restart();do{Start-Sleep -Milliseconds 20;$data=Get-Content -LiteralPath $report -Raw | ConvertFrom-Json}while($null -eq $data.PSObject.Properties['Reopened'] -and $deadline.Elapsed.TotalSeconds -lt 10);$reopenMs=$reopen.Elapsed.TotalMilliseconds;$second.WaitForExit();if($second.ExitCode -ne 0){throw 'Secondary activation failed'} } finally { $second.Dispose() }
            $p.Refresh();$rows+=[pscustomobject]@{Run=$run;Kind=$(if($run -eq 1){'new native extraction cache + new payload cache (OS cache uncontrolled)'}else{'native + payload cache hit'});FirstVisibleMs=$data.FirstVisible;FirstPaintMs=$data.FirstPaint;FirstStatusMs=$data.FirstStatus;PayloadReadyMs=$data.PayloadReady;ExtractMs=$data.ExtractMs;VerifyMs=$data.VerifyMs;CacheHit=$data.CacheHit;TrayOpenMs=$data.TrayOpenMilliseconds;ReopenViaSecondExeMs=$reopenMs;CpuPercentNormalized=$cpuPercent;CpuMillisecondsIn5Seconds=$cpuMs;WorkingSetMiB=($p.WorkingSet64/1MB);PrivateMiB=($p.PrivateMemorySize64/1MB)}
        } finally { if(-not $p.HasExited){$p.Kill();$p.WaitForExit()};$p.Dispose() }
    }
} finally { $env:DOTNET_BUNDLE_EXTRACT_BASE_DIR=$originalBundle }
$os=Get-CimInstance Win32_OperatingSystem; $cpu=Get-CimInstance Win32_Processor | Select-Object -First 1
$result=[pscustomobject]@{Time=[DateTimeOffset]::Now.ToString('o');Exe=$Exe;ExeBytes=(Get-Item -LiteralPath $Exe).Length;ExeSha256=(Get-FileHash -LiteralPath $Exe -Algorithm SHA256).Hash;OS=$os.Caption;Build=$os.Version;CPU=$cpu.Name;LogicalProcessors=[Environment]::ProcessorCount;RAMGiB=([double]$os.TotalVisibleMemorySize/1MB);Network='isolated fixture, no proxy/tasks/network mutation';Defender='not disabled; influence not independently measured';Cold='fresh native bundle and payload directories; not OS-cold or reboot-cold';Rows=$rows}
$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $OutputDirectory 'results.json') -Encoding UTF8
$rows | Format-Table

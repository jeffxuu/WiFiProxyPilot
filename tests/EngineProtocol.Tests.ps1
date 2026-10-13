# One focused race regression. Parse only the helper declaration; never execute Control.ps1.
Case 'V32 updated disk payload cannot authorize an old or unconfirmed resident watcher' {
    $dir=Join-Path ([IO.Path]::GetTempPath()) ('WiFiProtocol-'+[Guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory((Join-Path $dir 'state')) | Out-Null
    $name='WiFiProxyTest.Protocol.'+[Guid]::NewGuid().ToString('N'); $job=$null
    try {
        $tokens=$null; $errors=$null
        $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'Control.ps1'),[ref]$tokens,[ref]$errors)
        $declaration=$ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Assert-ManagementEngineProtocol'},$false)
        Check ($null -ne $declaration -and $errors.Count -eq 0)
        . ([scriptblock]::Create($declaration.Extent.Text))
        [IO.File]::WriteAllText((Join-Path $dir 'ProxyWatcher.ps1'),'$script:EngineProtocol=2')
        $ready=Join-Path $dir 'locked.signal'
        $job=Start-Job -ScriptBlock {
            param($mutexName,$readyPath)
            $mutex=[Threading.Mutex]::new($false,$mutexName); $owned=$false
            try { $owned=$mutex.WaitOne(0); if (-not $owned) { throw 'Test mutex collision' }; [IO.File]::WriteAllText($readyPath,'ready'); Start-Sleep -Seconds 30 }
            finally { if ($owned) { $mutex.ReleaseMutex() }; $mutex.Dispose() }
        } -ArgumentList $name,$ready
        $clock=[Diagnostics.Stopwatch]::StartNew()
        while (-not (Test-Path -LiteralPath $ready) -and $clock.Elapsed.TotalSeconds -lt 15) { Start-Sleep -Milliseconds 50 }
        Check (Test-Path -LiteralPath $ready) 'Test worker did not acquire the isolated mutex'
        $script:protocolTestMutex=$name
        function New-UserMutex([string]$Purpose) { Check ($Purpose -eq 'Watcher'); [Threading.Mutex]::new($false,$script:protocolTestMutex) }
        $path=Join-Path $dir 'state/status.json'
        foreach ($sample in @(
            @{Time=[DateTimeOffset]::Now.ToString('o');EngineVersion='3.1.0';SchemaVersion=1;Outcome='Enable';RunId='old'},
            @{Time=[DateTimeOffset]::Now.AddMinutes(-2).ToString('o');EngineVersion='3.2.0-beta.1';SchemaVersion=2;Outcome='Enable';RunId='stale'}
        )) {
            Write-JsonAtomic $path $sample; $rejected=$false
            try { Assert-ManagementEngineProtocol $dir } catch { $rejected=$_.Exception.Data['WiFiProxyCode'] -eq 'EngineUpgradeRequired' }
            Check $rejected 'Disk marker must not bypass the resident watcher protocol check'
        }
        Write-JsonAtomic $path @{Time=[DateTimeOffset]::Now.ToString('o');EngineVersion='3.2.0-beta.1';SchemaVersion=2;Outcome='Enable';RunId='current';PollSeconds=5}
        Assert-ManagementEngineProtocol $dir
        Check (-not (Test-Path -LiteralPath (Join-Path $dir 'config.json')) -and -not (Test-Path -LiteralPath (Join-Path $dir 'state/check.request'))) 'Protocol validation must stay read-only'
    } finally {
        if ($null -ne $job) { Stop-Job $job -ErrorAction SilentlyContinue; Remove-Job $job -Force -ErrorAction SilentlyContinue }
        Remove-TestFixture $dir
    }
}

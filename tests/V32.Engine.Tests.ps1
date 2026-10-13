# Loaded by Run-Tests.ps1. Configuration files and injected services are isolated; no real proxy/task writes.
Case 'V32 schema migration preserves user rules and old pause intent without adding rules' {
    $dir=Join-Path ([IO.Path]::GetTempPath()) ('WiFiV32-'+[Guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory((Join-Path $dir 'state')) | Out-Null
    try {
        $c=Clone-Config; $c.PSObject.Properties.Remove('SchemaVersion'); $c.PSObject.Properties.Remove('ManagementIntent'); $c.PSObject.Properties.Remove('SetupComplete')
        $c.Whitelist=@('User Network','user network',' Network ')
        $p=Join-Path $dir 'config.json'; Write-JsonAtomic $p $c
        $m=Read-Configuration $p; Check ($m.SchemaVersion -eq 2 -and $m.SetupComplete -and $m.ManagementIntent -eq 'Monitoring' -and $m.Whitelist.Count -eq 2)
        Write-JsonAtomic (Join-Path $dir 'state/pause.request') @{Time='legacy'}
        $m=Read-Configuration $p; Check ($m.ManagementIntent -eq 'Paused')
        $m.ManagementIntent='Direct'; Write-JsonAtomic $p $m
        Check ((Read-Configuration $p).ManagementIntent -eq 'Direct') 'Persisted intent must supersede the legacy pause marker'
        $m.Whitelist=@(); Write-JsonAtomic $p $m; Check ((Read-Configuration $p).Whitelist.Count -eq 0)
    } finally { Remove-TestFixture $dir }
}
Case 'V32 paused and direct cycles report observed network/proxy without changing either' {
    foreach ($intent in @('Paused','Direct')) {
        $services=New-Harness; $state=New-MonitorState; $c=Clone-Config; $c.SetupComplete=$true; $c.ManagementIntent=$intent; $c.Diagnostics='None'
        $script:h.Actual.Enable=$true
        Invoke-AutomaticMonitorCycle $state $c $services 0 | Out-Null
        Invoke-AutomaticMonitorCycle $state $c $services 1 | Out-Null
        Check ($script:h.Writes -eq 0 -and $script:h.ReadCount -gt 0 -and $script:h.LastHeartbeat.ActualEnabled -and $script:h.LastHeartbeat.NetworkKind -eq 'Connected')
        Check ($script:h.LastHeartbeat.Target -eq $intent -and $script:h.LastHeartbeat.SSID -eq 'Other')
    }
}
Case 'V32 resume and fresh evaluation discard the old network and diagnostic stability' {
    $services=New-Harness; $state=New-MonitorState; $c=Clone-Config; $c.SetupComplete=$true; $c.ManagementIntent='Paused'; $c.Diagnostics='None'
    Invoke-AutomaticMonitorCycle $state $c $services 0 | Out-Null; Invoke-AutomaticMonitorCycle $state $c $services 1 | Out-Null
    $script:h.Network=Snapshot (Link 'Changed' '192.0.2.1'); $c.ManagementIntent='Monitoring'
    Invoke-AutomaticMonitorCycle $state $c $services 2 | Out-Null; Check ($script:h.Writes -eq 0)
    Invoke-AutomaticMonitorCycle $state $c $services 3 | Out-Null; Check ($script:h.Writes -eq 1 -and $script:h.Actual.Server -eq '192.0.2.1:7890')
    $state.Health.Health='Unavailable'; Reset-MonitorEvaluation $state
    Check ($state.Health.Health -eq 'Unknown' -and $state.Stability.Key -eq '')
    Invoke-AutomaticMonitorCycle $state $c $services 4 | Out-Null; Check (-not $script:h.LastHeartbeat.Stable)
}
Case 'V32 a configuration/intent change at the apply gate cancels the stale decision' {
    $services=New-Harness; $state=New-MonitorState; $c=Clone-Config; $c.SetupComplete=$true; $c.ManagementIntent='Monitoring'; $c.Diagnostics='None'
    $services.Apply={param($target) [pscustomobject]@{Changed=$false;Snapshot=$null;Cancelled=$true}}
    Invoke-AutomaticMonitorCycle $state $c $services 0 | Out-Null
    $cycle=Invoke-AutomaticMonitorCycle $state $c $services 1
    Check ($script:h.Writes -eq 0 -and $state.Stability.Key -eq '' -and $cycle.WaitMs -eq 100)
}
Case 'V32 Direct persists intent before one manual-proxy disable and keeps original backup' {
    $dir=Join-Path ([IO.Path]::GetTempPath()) ('WiFiV32-'+[Guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory((Join-Path $dir 'state')) | Out-Null
    try {
        $c=Clone-Config; $c.SetupComplete=$true; $c.ManagementIntent='Monitoring'; $c.Whitelist=@('User Network')
        Write-JsonAtomic (Join-Path $dir 'config.json') $c
        $p=Join-Path $dir 'state/proxy-before-install.json'; Write-JsonAtomic $p (Registry-Snapshot $false 'original.example:80' '<local>')
        $before=[IO.File]::ReadAllBytes($p); $script:v32DirectRoot=$dir; $script:v32DirectWrites=0
        function Set-TargetProxy($target) {
            Check ((Read-Configuration (Join-Path $script:v32DirectRoot 'config.json')).ManagementIntent -eq 'Direct')
            Check ($target.Action -eq 'Disable'); $script:v32DirectWrites++
            [pscustomobject]@{Changed=$true;Snapshot=(Registry-Snapshot $false 'current.example:80' 'existing.bypass')}
        }
        Set-OwnedDirectMode ([pscustomobject]@{Root=$dir}) | Out-Null
        $saved=Read-Configuration (Join-Path $dir 'config.json')
        Check ($saved.ManagementIntent -eq 'Direct' -and $saved.Whitelist.Count -eq 1 -and $script:v32DirectWrites -eq 1)
        Check ([Convert]::ToBase64String($before) -ceq [Convert]::ToBase64String([IO.File]::ReadAllBytes($p)))
        Set-ManagementIntent $dir 'Paused' | Out-Null; Check ((Read-Configuration (Join-Path $dir 'config.json')).ManagementIntent -eq 'Paused')
    } finally { Remove-TestFixture $dir }
}

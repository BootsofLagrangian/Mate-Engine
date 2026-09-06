param([Parameter(Mandatory=$true)][string]$HelperPath,[Parameter(Mandatory=$true)][string]$FixturePath,[Parameter(Mandatory=$true)][string]$ResultPath)
$ErrorActionPreference='Stop'
$directory=Join-Path ([IO.Path]::GetTempPath()) ('mate-geometry-test-'+[Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($directory) | Out-Null
$output=Join-Path $directory 'snapshot.json'
$worker=$null; $fixture=$null
function Snapshot {
    for ($i=0;$i -lt 40;$i++) {
        if (Test-Path -LiteralPath $output) {
            try { return ([IO.File]::ReadAllText($output) | ConvertFrom-Json) } catch {}
        }
        Start-Sleep -Milliseconds 250
    }
    throw 'No snapshot received'
}
try {
    $fixture=Start-Process powershell.exe -ArgumentList @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',('"'+$FixturePath+'"'),'-Directory',('"'+$directory+'"')) -WindowStyle Hidden -PassThru
    $worker=Start-Process powershell.exe -RedirectStandardError (Join-Path $directory 'worker.err') -ArgumentList @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',('"'+$HelperPath+'"'),'-OutputPath',('"'+$output+'"'),'-OwnerPid',$PID) -WindowStyle Hidden -PassThru
    $infoPath=Join-Path $directory 'fixture.json'
    for ($i=0;$i -lt 40 -and -not (Test-Path -LiteralPath $infoPath);$i++) { Start-Sleep -Milliseconds 250 }
    $info=[IO.File]::ReadAllText($infoPath) | ConvertFrom-Json
    $first=Snapshot
    $own=@($first.windows | Where-Object id -eq $info.id)
    for ($i=0;$i -lt 10 -and $own.Count -ne 1;$i++) { Start-Sleep -Milliseconds 1000; $first=Snapshot; $own=@($first.windows | Where-Object id -eq $info.id) }
    if ($own.Count -ne 1) { throw 'Dedicated test window missing from geometry' }
    if (@($first.monitors).Count -lt 1) { throw 'Monitor geometry missing' }
    if ($first.version -ne 1) { throw 'Wrong contract version' }
    if ($own[0].width -lt 300 -or $own[0].height -lt 200) { throw 'Test window dimensions incorrect' }
    [IO.File]::WriteAllText((Join-Path $directory 'fixture.command'),'move')
    Start-Sleep -Milliseconds 2200
    $moved=Snapshot; $after=@($moved.windows | Where-Object id -eq $info.id)
    if ($after.Count -ne 1 -or $after[0].x-$own[0].x -ne 80 -or $after[0].y-$own[0].y -ne 60) { throw ('Movement/stable ID mismatch: '+($own | ConvertTo-Json -Compress)+' -> '+($after | ConvertTo-Json -Compress)+' worker error '+[IO.File]::ReadAllText((Join-Path $directory 'worker.err'))) }
    [IO.File]::WriteAllText((Join-Path $directory 'fixture.command'),'minimize')
    Start-Sleep -Milliseconds 2200
    $minimized=Snapshot
    if (@($minimized.windows | Where-Object id -eq $info.id).Count -ne 0) { throw 'Minimized window was not filtered' }
    if (@($minimized.windows | Where-Object { $_.id.StartsWith($PID.ToString()+':') -or $_.id.StartsWith($worker.Id.ToString()+':') }).Count -ne 0) { throw 'Owner/helper window not excluded' }
    [IO.File]::WriteAllText(($output+'.stop'),'stop')
    if (-not $worker.WaitForExit(4000)) { throw 'Worker did not honor stop sentinel' }
    $report=@{result='PASS';version=$first.version;monitor_count=@($first.monitors).Count;fixture_before=$own[0];fixture_after=$after[0];minimized_filtered=$true;owner_helper_excluded=$true;worker_stop_clean=$true;timestamp_advanced=($moved.timestamp_msec -gt $first.timestamp_msec)}
    $report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $ResultPath
    $report | ConvertTo-Json -Depth 6 -Compress
} finally {
    [IO.File]::WriteAllText((Join-Path $directory 'fixture.stop'),'stop')
    if ($null -ne $fixture -and -not $fixture.WaitForExit(3000)) { Stop-Process -Id $fixture.Id -ErrorAction SilentlyContinue }
    if ($null -ne $worker -and -not $worker.HasExited) { Stop-Process -Id $worker.Id -ErrorAction SilentlyContinue }
    Remove-Item -LiteralPath $directory -Recurse -Force -ErrorAction SilentlyContinue
}

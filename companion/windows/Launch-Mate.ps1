param(
    [string]$Distro = "",
    [string]$BackendRoot = "",
    [string]$Executable = "",
    [switch]$StopBackend
)
$ErrorActionPreference = "Stop"
$configPath = Join-Path $PSScriptRoot "runtime-location.json"
if (Test-Path -LiteralPath $configPath) {
    $location = Get-Content -Raw -LiteralPath $configPath | ConvertFrom-Json
    if (-not $Distro) { $Distro = [string]$location.distro }
    if (-not $BackendRoot) { $BackendRoot = [string]$location.backend_root }
}
if (-not $Distro -or -not $BackendRoot) {
    throw "Supply -Distro and -BackendRoot (Linux companion directory), or build with setup_native.py --build first."
}
if ($StopBackend) {
    & wsl.exe --distribution $Distro --cd $BackendRoot --exec python3 desktop.py stop
    if ($LASTEXITCODE -ne 0) { throw "Backend shutdown failed." }
    exit 0
}
if (-not $Executable) { $Executable = Join-Path $PSScriptRoot "MateCompanion.exe" }
if (-not (Test-Path -LiteralPath $Executable)) { throw "Native executable missing: $Executable" }
# argv is passed directly to WSL; workspace paths are never interpolated into shell code.
$jobRoot = $BackendRoot.TrimEnd('/') + "/user-data/workspace"
& wsl.exe --distribution $Distro --cd $BackendRoot --exec mkdir -p -- $jobRoot
if ($LASTEXITCODE -ne 0) { throw "Cannot prepare the work-agent directory." }
& wsl.exe --distribution $Distro --cd $BackendRoot --exec python3 desktop.py start --job-root $jobRoot --job-sandbox workspace-write
if ($LASTEXITCODE -ne 0) { throw "GPU backend failed to start; inspect companion/logs/desktop-runtime.log." }
Write-Host "Waiting for GPU models..."
$deadline = [DateTime]::UtcNow.AddMinutes(4)
$ready = $false
while ([DateTime]::UtcNow -lt $deadline) {
    try {
        $health = Invoke-RestMethod -Uri "http://127.0.0.1:8876/health" -TimeoutSec 3
        if ($health.ok -and $health.tts_ready -and $health.provider.loaded -and -not $health.provider.poisoned) {
            $ready = $true
            break
        }
    } catch { }
    Start-Sleep -Milliseconds 750
}
if (-not $ready) { throw "GPU backend did not become reachable. See companion/logs/desktop-engine.log." }
Start-Process -FilePath $Executable -WorkingDirectory (Split-Path -Parent $Executable)
Write-Host "Mate Companion started. F8: panel, F9: push to talk, Escape: interrupt."

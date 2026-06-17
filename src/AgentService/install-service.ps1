<#
.SYNOPSIS
    Registers Hermes Agent as a scheduled task (SYSTEM-level service) that starts at boot.
#>
param(
    [string]$HermesDir,
    [string]$TargetDir
)

$TASK_NAME = "HermesAgentService"
$TASK_DESC = "Agentic Windows — Hermes Agent system service (boot-time startup)"

# Find hermes.exe
$hermesPaths = @(
    "$HermesDir\hermes-agent\Scripts\hermes.exe",
    "$HermesDir\bin\hermes.exe",
    "$env:LOCALAPPDATA\hermes\hermes-agent\Scripts\hermes.exe",
    "$env:LOCALAPPDATA\hermes\bin\hermes.exe"
)

$hermesExe = $null
foreach ($p in $hermesPaths) {
    if (Test-Path $p) { $hermesExe = $p; break }
}

if (-not $hermesExe) {
    # Try to find it via PATH
    $hermesExe = (Get-Command "hermes" -ErrorAction SilentlyContinue).Source
}

if (-not $hermesExe) {
    Write-Host "  ❌ Hermes executable not found. Install Hermes first." -ForegroundColor Red
    exit 1
}

Write-Host "  ℹ️  Found Hermes at: $hermesExe" -ForegroundColor Cyan

# Create the scheduled task
$action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$TargetDir\agent-startup.ps1`"" `
    -WorkingDirectory $TargetDir

$trigger = New-ScheduledTaskTrigger -AtStartup

$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 1) `
    -ExecutionTimeLimit (New-TimeSpan -Days 365) `
    -Priority 4

$principal = New-ScheduledTaskPrincipal `
    -UserId "SYSTEM" `
    -LogonType ServiceAccount `
    -RunLevel Highest

try {
    Register-ScheduledTask `
        -TaskName $TASK_NAME `
        -Action $action `
        -Trigger $trigger `
        -Settings $settings `
        -Principal $principal `
        -Description $TASK_DESC `
        -Force

    Write-Host "  ✅ Scheduled task '$TASK_NAME' created." -ForegroundColor Green
    Write-Host "  ℹ️  Runs as SYSTEM at boot. Starts Hermes agent automatically." -ForegroundColor Cyan
} catch {
    Write-Host "  ❌ Failed to create scheduled task: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Optional: Start the task immediately to verify
try {
    Start-ScheduledTask -TaskName $TASK_NAME -ErrorAction SilentlyContinue
    Write-Host "  ℹ️  Task started. Agent is now running as SYSTEM." -ForegroundColor Cyan
} catch {
    Write-Host "  ℹ️  Task registered. Will start at next boot." -ForegroundColor Cyan
}

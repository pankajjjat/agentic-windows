<#
.SYNOPSIS
    Startup script for Hermes Agent system service.
    Called by Scheduled Task at boot. Runs as SYSTEM.
#>

$ErrorActionPreference = "SilentlyContinue"
$logFile = "$PSScriptRoot\logs\agent-startup-$(Get-Date -Format 'yyyyMMdd').log"

function Write-Log {
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[$timestamp] $($args[0])" | Out-File -Append -FilePath $logFile
}

Write-Log "Agentic Windows service starting..."

# 1. Find Hermes
$hermesDirs = @(
    "$env:LOCALAPPDATA\hermes\hermes-agent\Scripts\hermes.exe",
    "$env:LOCALAPPDATA\hermes\bin\hermes.exe",
    "$env:ProgramFiles\hermes\hermes-agent\Scripts\hermes.exe",
    "$env:ProgramFiles\hermes\bin\hermes.exe"
)

$hermesExe = $null
foreach ($d in $hermesDirs) {
    if (Test-Path $d) { $hermesExe = $d; break }
}

if (-not $hermesExe) {
    Write-Log "ERROR: Hermes executable not found."
    exit 1
}

Write-Log "Found Hermes: $hermesExe"

# 2. Configure Hermes environment
$env:HERMES_CONFIG = "$env:LOCALAPPDATA\hermes\config.yaml"
$env:TERM = "xterm-256color"

# 3. Start Hermes in daemon mode
try {
    $process = Start-Process -FilePath $hermesExe `
        -ArgumentList "run" `
        -WindowStyle Hidden `
        -WorkingDirectory "$env:LOCALAPPDATA\hermes" `
        -PassThru
    
    Write-Log "Hermes started (PID: $($process.Id))"
    
    # Verify it's running
    Start-Sleep -Seconds 5
    if (Get-Process -Id $process.Id -ErrorAction SilentlyContinue) {
        Write-Log "Hermes is running successfully"
    } else {
        Write-Log "WARNING: Hermes process exited unexpectedly"
    }
} catch {
    Write-Log "ERROR starting Hermes: $($_.Exception.Message)"
}

# 4. Start Dashboard Server (Python)
$dashboardServer = "$PSScriptRoot\Dashboard\server.py"
if (Test-Path $dashboardServer) {
    try {
        $pyExe = "python"
        # Try to find Python from Hermes environment
        $pythonPaths = @(
            "$env:LOCALAPPDATA\hermes\hermes-agent\Scripts\python.exe",
            "$env:LOCALAPPDATA\hermes\python\python.exe",
            "python"
        )
        foreach ($pp in $pythonPaths) {
            if (Test-Path $pp) { $pyExe = $pp; break }
        }

        $dashboardProcess = Start-Process -FilePath $pyExe `
            -ArgumentList "`"$dashboardServer`"" `
            -WindowStyle Hidden `
            -PassThru
        
        Write-Log "Dashboard server started (PID: $($dashboardProcess.Id))"
        Start-Sleep -Seconds 2
    } catch {
        Write-Log "WARNING: Could not start dashboard server: $($_.Exception.Message)"
    }
} else {
    Write-Log "Dashboard server not found at: $dashboardServer"
}

Write-Log "Agentic Windows service started successfully"

# Keep this script running so the scheduled task stays alive
$hermesProcess = $process
$dashProcess = $dashboardProcess

while ($true) {
    Start-Sleep -Seconds 60
    
    # Health check: restart Hermes if it crashed
    if ($hermesProcess -and -not (Get-Process -Id $hermesProcess.Id -ErrorAction SilentlyContinue)) {
        Write-Log "Hermes process died. Restarting..."
        try {
            $hermesProcess = Start-Process -FilePath $hermesExe `
                -ArgumentList "run" `
                -WindowStyle Hidden `
                -WorkingDirectory "$env:LOCALAPPDATA\hermes" `
                -PassThru
            Write-Log "Restarted Hermes (PID: $($hermesProcess.Id))"
        } catch {
            Write-Log "ERROR restarting Hermes: $($_.Exception.Message)"
        }
    }
    
    # Health check: restart dashboard if it crashed
    if ($dashProcess -and -not (Get-Process -Id $dashProcess.Id -ErrorAction SilentlyContinue)) {
        Write-Log "Dashboard server died. Restarting..."
        try {
            $dashProcess = Start-Process -FilePath $pyExe `
                -ArgumentList "`"$dashboardServer`"" `
                -WindowStyle Hidden `
                -PassThru
            Write-Log "Restarted dashboard (PID: $($dashProcess.Id))"
        } catch {
            Write-Log "ERROR restarting dashboard: $($_.Exception.Message)"
        }
    }
}

<#
.SYNOPSIS
    Hermes Agent service startup with self-healing watchdog.
    Runs as SYSTEM via scheduled task at boot.
    Monitors Hermes and Dashboard processes, restarts on crash,
    and watches for system events (logon, logoff, shutdown).
#>

$ErrorActionPreference = "SilentlyContinue"

# ═══════════════════════════════════════════
# Configuration
# ═══════════════════════════════════════════
$LOG_DIR = "$PSScriptRoot\logs"
$MAX_RETRIES = 5                # Max consecutive restart attempts
$HEALTH_CHECK_INTERVAL = 30     # Seconds between health checks
$BACKOFF_BASE = 10              # Base seconds for exponential backoff

# Ensure log directory exists
if (-not (Test-Path $LOG_DIR)) { New-Item -ItemType Directory -Path $LOG_DIR -Force | Out-Null }

# Log rotation — keep 7 days
Get-ChildItem "$LOG_DIR\*.log" -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-7) } |
    Remove-Item -Force -ErrorAction SilentlyContinue

$logFile = "$LOG_DIR\agent-service-$(Get-Date -Format 'yyyyMMdd').log"

function Write-Log {
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $msg = "[$timestamp] $($args[0])"
    $msg | Out-File -Append -FilePath $logFile -Encoding UTF8
    Write-Host $msg
}

function Write-SystemEvent {
    # Log to Windows Event Log for visibility
    try {
        $msg = $args[0]
        $eventId = $args[1]
        if (-not (Get-EventLog -LogName Application -Source "AgenticWindows" -ErrorAction SilentlyContinue)) {
            New-EventLog -LogName Application -Source "AgenticWindows" -ErrorAction SilentlyContinue | Out-Null
        }
        Write-EventLog -LogName Application -Source "AgenticWindows" -EventId $eventId -EntryType Information -Message $msg -ErrorAction SilentlyContinue
    } catch { }
}

function Start-WithRetry {
    param(
        [string]$Name,
        [string]$FilePath,
        [string]$Arguments,
        [string]$WorkDir
    )
    $attempt = 0
    $lastPid = $null
    while ($attempt -lt $MAX_RETRIES) {
        $attempt++
        try {
            $proc = Start-Process -FilePath $FilePath -ArgumentList $Arguments -WindowStyle Hidden -WorkingDirectory $WorkDir -PassThru
            $pid = $proc.Id
            Write-Log "$Name started (PID: $pid, attempt $attempt/$MAX_RETRIES)"
            $lastPid = $pid
            return $proc
        } catch {
            $wait = [Math]::Min($BACKOFF_BASE * [Math]::Pow(2, $attempt - 1), 120)
            Write-Log "WARNING: Failed to start $Name (attempt $attempt/$MAX_RETRIES): $($_.Exception.Message)"
            if ($attempt -lt $MAX_RETRIES) {
                Write-Log "  Retrying in ${wait}s..."
                Start-Sleep -Seconds $wait
            }
        }
    }
    Write-Log "ERROR: $Name failed to start after $MAX_RETRIES attempts"
    return $null
}

# ═══════════════════════════════════════════
# 1. Find Hermes executable
# ═══════════════════════════════════════════
Write-Log "Agentic Windows service starting..."

$hermesPaths = @(
    "$env:LOCALAPPDATA\hermes\hermes-agent\Scripts\hermes.exe",
    "$env:LOCALAPPDATA\hermes\bin\hermes.exe",
    "$env:ProgramFiles\hermes\hermes-agent\Scripts\hermes.exe",
    "$env:ProgramFiles\hermes\bin\hermes.exe",
    "$env:USERPROFILE\.local\bin\hermes.exe",
    "$env:USERPROFILE\AppData\Roaming\npm\hermes.cmd"
)

$hermesExe = $null
foreach ($d in $hermesPaths) {
    if (Test-Path $d) { $hermesExe = $d; break }
}

if (-not $hermesExe) {
    $hermesExe = (Get-Command "hermes" -ErrorAction SilentlyContinue).Source
}

if (-not $hermesExe) {
    Write-Log "ERROR: Hermes executable not found after checking all paths."
    Write-SystemEvent "Hermes executable not found. Agentic Windows service will not start." 1001
    exit 1
}

Write-Log "Found Hermes: $hermesExe"
Write-SystemEvent "Hermes Agent service starting (PID check, binary: $hermesExe)" 1000

$env:HERMES_CONFIG = "$env:LOCALAPPDATA\hermes\config.yaml"
$env:TERM = "xterm-256color"

$hermesDir = Split-Path (Split-Path $hermesExe -Parent) -Parent
if (-not $hermesDir) { $hermesDir = "$env:LOCALAPPDATA\hermes" }

# ═══════════════════════════════════════════
# 2. Start processes
# ═══════════════════════════════════════════
Write-Log "Starting Hermes daemon..."
$hermesProcess = Start-WithRetry -Name "Hermes" -FilePath $hermesExe -Arguments "run" -WorkDir $hermesDir
Start-Sleep -Seconds 3

# Verify Hermes is responsive
if ($hermesProcess) {
    $hermesPid = $hermesProcess.Id
    if (Get-Process -Id $hermesPid -ErrorAction SilentlyContinue) {
        Write-Log "Hermes daemon is running (PID: $hermesPid)"
    }
}

# Dashboard server
$dashboardServer = "$PSScriptRoot\Dashboard\server.py"
$dashboardProcess = $null
if (Test-Path $dashboardServer) {
    Write-Log "Starting Dashboard server..."
    
    # Find Python
    $pythonPaths = @(
        "$env:LOCALAPPDATA\hermes\hermes-agent\Scripts\python.exe",
        "$env:LOCALAPPDATA\hermes\python\python.exe",
        "$env:ProgramFiles\Python313\python.exe",
        "python"
    )
    $pyExe = $null
    foreach ($pp in $pythonPaths) {
        if (Test-Path $pp) { $pyExe = $pp; break }
    }
    if (-not $pyExe) { $pyExe = (Get-Command "python3" -ErrorAction SilentlyContinue).Source }
    if (-not $pyExe) { $pyExe = (Get-Command "python" -ErrorAction SilentlyContinue).Source }
    
    if ($pyExe) {
        $dashboardProcess = Start-WithRetry -Name "Dashboard" -FilePath $pyExe -Arguments "`"$dashboardServer`"" -WorkDir "$PSScriptRoot\Dashboard"
        if ($dashboardProcess) {
            Write-Log "Dashboard server started (PID: $($dashboardProcess.Id))"
        }
    } else {
        Write-Log "WARNING: Python not found. Dashboard will not start."
    }
} else {
    Write-Log "Dashboard server not found at: $dashboardServer"
}

# ═══════════════════════════════════════════
# 3. Start WMI system event watcher (background)
# ═══════════════════════════════════════════
$wmiScript = @'
$logFile = "{0}"
$hermesBin = "{1}"
$hermesDir = "{2}"
function Write-Log {{
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[$timestamp] [WMI-Watcher] $($args[0])" | Out-File -Append -FilePath $logFile -Encoding UTF8
}}

# Watch for system events
$queries = @(
    # Logon/Logoff events (Event ID 7001, 7002 for Terminal Services)
    "SELECT * FROM Win32_NTLogEvent WHERE LogFile='Security' AND EventCode=4624",
    # System shutdown (Event ID 1074)
    "SELECT * FROM Win32_NTLogEvent WHERE LogFile='System' AND EventCode=1074",
    # Disk warning (Event ID 157)
    "SELECT * FROM Win32_NTLogEvent WHERE LogFile='System' AND EventCode=157"
)

Write-Log "WMI Event Watcher started"

foreach ($query in $queries) {{
    try {{
        Register-WmiEvent -Query $query -Action {{
            $event = $EventArgs.NewEvent
            $msg = "System event: $($event.EventCode) - $($event.Message.Substring(0,[Math]::Min(200, $event.Message.Length)))"
            Write-Log $msg
        }} -ErrorAction SilentlyContinue
    }} catch {{ }}
}}

# Keep-alive
while ($true) {{ Start-Sleep -Seconds 300 }}
'@ -f $logFile, $hermesExe, $hermesDir

$wmiScriptPath = "$PSScriptRoot\wmi-watcher.ps1"
$wmiScript | Out-File -FilePath $wmiScriptPath -Encoding UTF8 -Force
$wmiProcess = Start-Process -FilePath "powershell" -ArgumentList "-ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -File `"$wmiScriptPath`"" -PassThru
Write-Log "WMI event watcher started (PID: $($wmiProcess.Id))"

# ═══════════════════════════════════════════
# 4. Watchdog loop — self-healing
# ═══════════════════════════════════════════
Write-Log "Watchdog loop started (check interval: ${HEALTH_CHECK_INTERVAL}s)"
Write-SystemEvent "Agentic Windows service started successfully. Watchdog active." 1002

$hermesRestartCount = 0
$dashboardRestartCount = 0
$lastRestartTime = @{}

while ($true) {
    Start-Sleep -Seconds $HEALTH_CHECK_INTERVAL
    $now = Get-Date
    
    # ── Hermes health check ──
    if ($hermesProcess -and -not (Get-Process -Id $hermesProcess.Id -ErrorAction SilentlyContinue)) {
        $hermesRestartCount++
        $waitTime = [Math]::Min($BACKOFF_BASE * $hermesRestartCount, 300)
        Write-Log "WARNING: Hermes process died (restart #$hermesRestartCount). Restarting in ${waitTime}s..."
        Write-SystemEvent "Hermes Agent crashed. Restart attempt #$hermesRestartCount." 1003
        
        Start-Sleep -Seconds $waitTime
        
        # Kill any orphaned Hermes processes
        Get-Process -Name "hermes" -ErrorAction SilentlyContinue |
            Where-Object { $_.Id -ne $hermesProcess.Id } |
            Stop-Process -Force -ErrorAction SilentlyContinue
        
        $hermesProcess = Start-WithRetry -Name "Hermes" -FilePath $hermesExe -Arguments "run" -WorkDir $hermesDir
    } else {
        # Reset counter on stable run
        $hermesRestartCount = [Math]::Max(0, $hermesRestartCount - 1)
    }
    
    # ── Dashboard health check ──
    if ($dashboardProcess -and -not (Get-Process -Id $dashboardProcess.Id -ErrorAction SilentlyContinue)) {
        $dashboardRestartCount++
        Write-Log "WARNING: Dashboard server died (restart #$dashboardRestartCount). Restarting..."
        if ($pyExe) {
            $dashboardProcess = Start-WithRetry -Name "Dashboard" -FilePath $pyExe -Arguments "`"$dashboardServer`"" -WorkDir "$PSScriptRoot\Dashboard"
            $dashboardRestartCount = 0
        }
    }
    
    # ── WMI watcher health check ──
    if ($wmiProcess -and -not (Get-Process -Id $wmiProcess.Id -ErrorAction SilentlyContinue)) {
        Write-Log "WMI watcher died. Restarting..."
        $wmiProcess = Start-Process -FilePath "powershell" -ArgumentList "-ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -File `"$wmiScriptPath`"" -PassThru
        Write-Log "WMI watcher restarted (PID: $($wmiProcess.Id))"
    }
    
    # ── Reset counter after 1 hour of stability ──
    if ($hermesRestartCount -gt 0 -and (Get-Process -Id $hermesProcess.Id -ErrorAction SilentlyContinue)) {
        $stable = $true
        if ($stable -and ($now - $lastRestartTime.Hermes).TotalMinutes -gt 60) {
            $hermesRestartCount = 0
            Write-Log "Hermes stable for 60+ minutes. Restart counter reset."
        }
    }
}

# Keep script alive
Wait-Process -Id $hermesProcess.Id -ErrorAction SilentlyContinue

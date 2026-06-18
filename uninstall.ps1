<#
.SYNOPSIS
    Agentic Windows — Clean uninstaller. Removes all components installed by install.ps1.
.DESCRIPTION
    Removes: Hermes scheduled task, tray registry entry, dashboard server, skills,
    config changes, PowerShell profile entries, and optional kernel driver.
.NOTES
    Run as Administrator. Does NOT uninstall Hermes Agent or OpenCode (the user
    may want those for other projects).
#>

param(
    [switch]$Force,       # Skip confirmation prompts
    [switch]$RemoveHermes # Also uninstall Hermes Agent itself
)

$ErrorActionPreference = "Stop"

function Write-Info  { Write-Host "  ℹ️  $($args[0])" -ForegroundColor Cyan }
function Write-Good  { Write-Host "  ✅ $($args[0])" -ForegroundColor Green }
function Write-Warn  { Write-Host "  ⚠️  $($args[0])" -ForegroundColor Yellow }
function Write-Error { Write-Host "  ❌ $($args[0])" -ForegroundColor Red }

$TARGET_DIR = "$env:ProgramFiles\AgenticWindows"
$SERVICE_NAME = "HermesAgentService"
$TRAY_REG_NAME = "AgenticWindowsTray"
$DASHBOARD_PORT = 4774

Write-Info "Agentic Windows — Uninstaller"
Write-Info "Target: $TARGET_DIR"
Write-Info ""

if (-not $Force) {
    Write-Warn "This will remove all Agentic Windows components."
    Write-Warn "The following will be removed:"
    Write-Warn "  • $SERVICE_NAME scheduled task"
    Write-Warn "  • System tray + Win+Space hotkey"
    Write-Warn "  • Dashboard server ($TARGET_DIR\Dashboard\)"
    Write-Warn "  • Pre-loaded Hermes skills"
    Write-Warn "  • PowerShell profile entries"
    Write-Warn "  • Kernel driver (if installed)"
    Write-Info ""
    Write-Warn "Hermes Agent and OpenCode will NOT be removed (use -RemoveHermes for that)."
    $confirm = Read-Host "  Continue? (y/N) "
    if ($confirm -ne "y") { Write-Info "Aborted."; exit 0 }
}

# ─────────────── 1. Stop scheduled task ───────────────
Write-Info "Stopping $SERVICE_NAME scheduled task..."
try {
    $task = Get-ScheduledTask -TaskName $SERVICE_NAME -ErrorAction SilentlyContinue
    if ($task) {
        Stop-ScheduledTask -TaskName $SERVICE_NAME -ErrorAction SilentlyContinue
        Start-Sleep 1
        Unregister-ScheduledTask -TaskName $SERVICE_NAME -Confirm:$false
        Write-Good "Scheduled task removed"
    } else {
        Write-Info "No task found"
    }
} catch {
    Write-Warn "Could not remove task: $_"
}

# ─────────────── 2. Kill running processes ───────────────
Write-Info "Stopping running components..."
$processes = @("python", "hermes", "opencode")
foreach ($proc in $processes) {
    # Only kill processes started from our directory
    Get-Process -Name $proc -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            $path = $_.MainModule.FileName
            if ($path -like "*AgenticWindows*" -or $path -like "*hermes*") {
                $_.Kill()
                Write-Good "Killed $proc (PID $($_.Id))"
            }
        } catch { }
    }
}

# ─────────────── 3. Remove tray registry entry ───────────────
Write-Info "Removing tray auto-start..."
@(
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run\$TRAY_REG_NAME",
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run\$TRAY_REG_NAME"
) | ForEach-Object {
    try {
        Remove-ItemProperty -Path (Split-Path $_) -Name (Split-Path $_ -Leaf) -ErrorAction SilentlyContinue
        Write-Good "Removed $_"
    } catch { }
}

# ─────────────── 4. Remove program files ───────────────
Write-Info "Removing $TARGET_DIR..."
if (Test-Path $TARGET_DIR) {
    try {
        Remove-Item -Path $TARGET_DIR -Recurse -Force
        Write-Good "Removed $TARGET_DIR"
    } catch {
        Write-Warn "Could not fully remove $TARGET_DIR (files may be in use): $_"
    }
} else {
    Write-Info "Directory not found"
}

# ─────────────── 5. Remove Hermes skills ───────────────
Write-Info "Removing Agentic Windows skills..."
$skillDir = "$env:USERPROFILE\.hermes\skills"
if (Test-Path $skillDir) {
    @("system-health", "disk-guardian", "process-manager", "memory-watchdog",
      "network-monitor", "update-manager", "dev-quickstart",
      "services-manager", "cleanup-tool") | ForEach-Object {
        $skillFile = "$skillDir\$_.md"
        if (Test-Path $skillFile) {
            Remove-Item $skillFile -Force
            Write-Good "Removed skill: $_"
        }
    }
}

# ─────────────── 6. Remove PowerShell profile entries ───────────────
Write-Info "Cleaning PowerShell profile..."
$profilePath = $PROFILE.CurrentUserAllHosts
if (Test-Path $profilePath) {
    $content = Get-Content $profilePath -Raw
    $lines = @(
        '# Agentic Windows',
        'Set-Alias agent hermes',
        'function sys-health',
        'function sys-disk',
        'function sys-process',
        'function sys-memory',
        'function sys-services',
        'function sys-cleanup',
        'function agent-help'
    )
    $newContent = $content
    foreach ($marker in @('DASHBOARD_PORT', 'Agentic Windows')) {
        $newContent = $newContent -replace "(?ms)\s*# ── Agentic Windows.*?# ── End Agentic Windows.*", ""
    }
    # Also remove individual marker lines
    $newContent = $newContent -replace "# ── Agentic Windows.*", ""
    $newContent = $newContent -replace "# ── End Agentic Windows.*", ""
    $newContent = $newContent -replace '# Agentic Windows.*', ''
    $newContent = $newContent.Trim()
    if ($newContent -ne $content.Trim()) {
        if ($newContent) {
            Set-Content -Path $profilePath -Value $newContent
        } else {
            Remove-Item $profilePath -Force
        }
        Write-Good "Cleaned PowerShell profile"
    } else {
        Write-Info "No profile entries found"
    }
}

# ─────────────── 7. Remove kernel driver ───────────────
Write-Info "Removing kernel driver (HermesCore.sys)..."
try {
    $driver = Get-Service -Name "HermesCore" -ErrorAction SilentlyContinue
    if ($driver) {
        Stop-Service -Name "HermesCore" -Force -ErrorAction SilentlyContinue
        Start-Sleep 2
        & sc.exe delete HermesCore 2>&1 | Out-Null
        Write-Good "Kernel driver removed"
    } else {
        Write-Info "No driver found"
    }
} catch {
    Write-Warn "Could not remove driver: $_"
}

# Remove driver file
$driverPath = "$env:SystemRoot\System32\drivers\hermes_core.sys"
if (Test-Path $driverPath) {
    try {
        Remove-Item $driverPath -Force
        Write-Good "Removed driver binary"
    } catch {
        Write-Warn "Could not remove $driverPath"
    }
}

# ─────────────── 8. Remove Hermes Agent (optional) ───────────────
if ($RemoveHermes) {
    Write-Info "Removing Hermes Agent..."
    try {
        $hermesPath = "$env:USERPROFILE\.hermes"
        if (Test-Path $hermesPath) {
            Remove-Item $hermesPath -Recurse -Force -ErrorAction SilentlyContinue
        }
        # Remove from PATH
        $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
        $userPath = ($userPath.Split(';') | Where-Object { $_ -notlike "*\.hermes*" }) -join ';'
        [Environment]::SetEnvironmentVariable("Path", $userPath, "User")
        Write-Good "Hermes Agent removed"
    } catch {
        Write-Warn "Could not fully remove Hermes: $_"
    }
}

# ─────────────── 9. Refresh environment ───────────────
$env:Path = [Environment]::GetEnvironmentVariable("Path", "User") + ";" +
            [Environment]::GetEnvironmentVariable("Path", "Machine")

Write-Info ""
Write-Good "Agentic Windows has been removed from this system."
Write-Info "A restart is recommended to clean up any remaining processes."

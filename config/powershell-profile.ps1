# ── Agentic Windows — PowerShell Profile ──
# Loaded into every PowerShell session

$env:HERMES_CONFIG = "$env:LOCALAPPDATA\hermes\config.yaml"
$env:DASHBOARD_PORT = "4775"

# Agent shortcut
function agent { hermes @args }

# Dashboard shortcut
function dash { Start-Process "http://localhost:$env:DASHBOARD_PORT" }

# Quick system commands
function sys-health { hermes run skill system-health }
function sys-disk { hermes run skill disk-guardian }
function sys-process { hermes run skill process-manager }
function sys-memory { hermes run skill memory-watchdog }
function sys-network { hermes run skill network-monitor }
function sys-updates { hermes run skill update-manager }
function dev-status { hermes run skill dev-quickstart }

# Prompt customization
function prompt {
    $shortDir = (Get-Location).Path.Replace($HOME, "~")
    "⚡ $shortDir> "
}

Write-Host "⚡ Agentic Windows active. Commands: agent, dash, sys-health, sys-disk, sys-process" -ForegroundColor Cyan

<#
.SYNOPSIS
    Install or uninstall Agentic Windows — transforms Win 11 into an agent-driven OS.
.DESCRIPTION
    Installs Hermes Agent as a system service, configures global hotkey + tray,
    deploys the web dashboard, and loads pre-built system-management skills.

    Run as Administrator for full system-wide installation.
    Run with -UserMode for a per-user installation (no service, no kernel driver).

.PARAMETER Install
    Run the full installation.
.PARAMETER Uninstall
    Remove all Agentic Windows components.
.PARAMETER UserMode
    Install without admin requirements (no system service, no kernel driver).
.PARAMETER SkipTools
    Skip dev tools installation (Python, Node.js, Git, VS Code, OpenCode).
.PARAMETER SkipDashboard
    Skip the web dashboard installation.
.PARAMETER Force
    Overwrite existing installation without prompting.
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File install.ps1 -Install
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File install.ps1 -Uninstall
#>

param(
    [switch]$Install,
    [switch]$Uninstall,
    [switch]$UserMode,
    [switch]$SkipTools,
    [switch]$SkipDashboard,
    [switch]$Force
)

# ──────────────────────────────────────────────
# Configuration
# ──────────────────────────────────────────────
$AGENTIC_DIR       = "$env:ProgramFiles\AgenticWindows"
$AGENTIC_DIR_USER  = "$env:LOCALAPPDATA\AgenticWindows"
$HERMES_DIR        = "$env:LOCALAPPDATA\hermes"
$SKILLS_DIR        = "$env:LOCALAPPDATA\hermes\skills"
$TASK_NAME         = "HermesAgentService"
$HOTKEY_REG_PATH   = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
$HOTKEY_REG_NAME   = "AgenticWindowsTray"
$DASHBOARD_PORT    = 4774
$REPO_URL          = "https://raw.githubusercontent.com/pankajjjat/agentic-windows/main"
$GITHUB_REPO       = "pankajjjat/agentic-windows"

# Colors
$C_INFO  = "Cyan"
$C_GOOD  = "Green"
$C_WARN  = "Yellow"
$C_ERROR = "Red"
$C_HL    = "Magenta"

function Write-Info  { Write-Host "  ℹ️  $($args[0])" -ForegroundColor $C_INFO }
function Write-Good  { Write-Host "  ✅ $($args[0])" -ForegroundColor $C_GOOD }
function Write-Warn  { Write-Host "  ⚠️  $($args[0])" -ForegroundColor $C_WARN }
function Write-Error { Write-Host "  ❌ $($args[0])" -ForegroundColor $C_ERROR }
function Write-Step  { Write-Host "`n  ──▶ $($args[0])" -ForegroundColor $C_HL }

# ──────────────────────────────────────────────
# Helper functions
# ──────────────────────────────────────────────

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-Architecture {
    return (Get-WmiObject Win32_Processor).AddressWidth
}

function Test-Windows11 {
    $ver = [Environment]::OSVersion.Version
    $build = $ver.Build
    $major = $ver.Major
    return ($major -ge 10 -and $build -ge 22000)
}

function Ensure-Directory {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        New-Item -Path $Path -ItemType Directory -Force | Out-Null
        Write-Info "Created directory: $Path"
    }
}

function Download-File {
    param([string]$Url, [string]$OutFile)
    try {
        Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing -ErrorAction Stop
        return $true
    } catch {
        Write-Warn "Download failed: $Url ($($_.Exception.Message))"
        return $false
    }
}

# ──────────────────────────────────────────────
# Main installation logic
# ──────────────────────────────────────────────

function Install-AgenticWindows {
    Write-Host "`n"
    Write-Host "  ╔══════════════════════════════════════════╗" -ForegroundColor $C_HL
    Write-Host "  ║        ⚡ AGENTIC WINDOWS SETUP          ║" -ForegroundColor $C_HL
    Write-Host "  ║  Transform your PC into an agentic OS    ║" -ForegroundColor $C_HL
    Write-Host "  ╚══════════════════════════════════════════╝" -ForegroundColor $C_HL
    Write-Host ""

    # ── Prerequisites ──
    Write-Step "Checking prerequisites"

    if (-not (Test-Windows11)) {
        Write-Error "Windows 11 (build 22000+) required. You have build $([Environment]::OSVersion.Version.Build)."
        return
    }
    Write-Good "Windows 11 detected (build $([Environment]::OSVersion.Version.Build))"

    $isAdmin = Test-Admin
    if (-not $isAdmin -and -not $UserMode) {
        Write-Warn "Not running as Administrator. Some features will be skipped."
        Write-Warn "Re-run as Administrator for full installation: right-click → 'Run as Administrator'"
        Write-Warn "Continuing in UserMode..."
        $script:UserMode = $true
    }

    if ($isAdmin) {
        Write-Good "Running with Administrator privileges"
    }

    # Check disk space
    $drive = Get-PSDrive -Name "C" -ErrorAction SilentlyContinue
    if ($drive -and $drive.Free -lt 5GB) {
        Write-Warn "Low disk space: $([math]::Round($drive.Free/1GB, 1)) GB free (recommended: 5+ GB)"
        if (-not $Force) {
            $confirm = Read-Host "  Continue anyway? (y/N)"
            if ($confirm -ne "y") { Write-Info "Installation cancelled."; return }
        }
    }

    # ── Install Hermes Agent ──
    Write-Step "Installing Hermes Agent"
    $hermesCmd = Get-Command "hermes" -ErrorAction SilentlyContinue
    if ($hermesCmd) {
        $hermesVersion = & $hermesCmd --version 2>&1 | Out-String
        Write-Good "Hermes Agent already installed ($($hermesVersion.Trim()))"
    } else {
        Write-Info "Downloading and running Hermes installer..."
        try {
            $installScript = Invoke-WebRequest -Uri "https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.ps1" -UseBasicParsing
            $tempFile = "$env:TEMP\install-hermes.ps1"
            $installScript.Content | Out-File -FilePath $tempFile -Encoding utf8
            & powershell -ExecutionPolicy Bypass -File $tempFile
            Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
            Write-Good "Hermes Agent installed"
        } catch {
            Write-Error "Hermes installation failed: $($_.Exception.Message)"
            Write-Info "You can install manually: https://hermes-agent.nousresearch.com/docs"
        }
    }

    # Refresh PATH to find hermes — append to existing, don't replace
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $env:Path = "$env:Path;$userPath;$machinePath"

    # ── Install OpenCode ──
    if (-not $SkipTools) {
        Write-Step "Installing developer tools"
        
        if (Get-Command "opencode" -ErrorAction SilentlyContinue) {
            Write-Good "OpenCode already installed"
        } else {
            if (Get-Command "npm" -ErrorAction SilentlyContinue) {
                # Ensure npm uses a user-writable prefix (avoids admin requirement)
                $npmRoot = npm root -g 2>$null
                if (-not $npmRoot -or $npmRoot -match "Program Files") {
                    $userNpmPrefix = "$env:APPDATA\npm"
                    if (-not (Test-Path $userNpmPrefix)) { New-Item -ItemType Directory -Path $userNpmPrefix -Force | Out-Null }
                    npm config set prefix "$userNpmPrefix" 2>$null
                    # Add to PATH if not already there
                    if ($env:Path -notlike "*$userNpmPrefix*") {
                        $env:Path = "$userNpmPrefix;$env:Path"
                        [Environment]::SetEnvironmentVariable("Path", "$userNpmPrefix;$([Environment]::GetEnvironmentVariable('Path', 'User'))", "User")
                    }
                    Write-Info "Configured npm to use user prefix: $userNpmPrefix"
                }

                Write-Info "Installing OpenCode (npm install -g opencode-ai)..."
                $opencodeOutput = npm install -g opencode-ai 2>&1
                $opencodeExit = $LASTEXITCODE
                if ($opencodeExit -eq 0) {
                    Write-Good "OpenCode installed globally"
                } else {
                    Write-Warn "OpenCode install had issues (exit $opencodeExit): $($opencodeOutput | Out-String)"
                    Write-Info "  Run manually: 'npm install -g opencode-ai' from a normal (non-admin) shell."
                }
            } else {
                Write-Warn "npm not found. Install Node.js first: winget install OpenJS.NodeJS.LTS"
            }
        }

        # Check for other dev tools
        $tools = @(
            @{Name="Python";     Cmd="python --version";   Winget="Python.Python.3.13"},
            @{Name="Node.js";    Cmd="node --version";     Winget="OpenJS.NodeJS"},
            @{Name="Git";        Cmd="git --version";      Winget="Git.Git"}
        )
        foreach ($tool in $tools) {
            $result = & cmd /c "$($tool.Cmd)" 2>$null
            if ($LASTEXITCODE -eq 0) {
                Write-Good "$($tool.Name): $($result.Trim())"
            } else {
                Write-Info "$($tool.Name) not found. Install: winget install $($tool.Winget)"
            }
        }
    }

    # ── Create installation directories ──
    Write-Step "Setting up Agentic Windows files"

    $targetDir = if ($UserMode) { $AGENTIC_DIR_USER } else { $AGENTIC_DIR }
    Ensure-Directory $targetDir
    Ensure-Directory "$targetDir\Dashboard"
    Ensure-Directory "$targetDir\skills"
    Ensure-Directory "$targetDir\logs"

    # ── Download and install components ──
    Write-Info "Downloading components from GitHub..."

    # Download tray app
    $trayUrl = "$REPO_URL/src/AgentTray/agent-tray.ps1"
    $trayFile = "$targetDir\agent-tray.ps1"
    if (Download-File $trayUrl $trayFile) {
        Write-Good "Tray app downloaded"
    }

    # Download startup script
    $startupUrl = "$REPO_URL/src/AgentService/agent-startup.ps1"
    $startupFile = "$targetDir\agent-startup.ps1"
    if (Download-File $startupUrl $startupFile) {
        Write-Good "Startup script downloaded"
    }

    # Download install-service script
    $svcUrl = "$REPO_URL/src/AgentService/install-service.ps1"
    $svcFile = "$targetDir\install-service.ps1"
    if (Download-File $svcUrl $svcFile) {
        Write-Good "Service installer downloaded"
    }

    # Download skills
    $skillNames = @(
        "system-health",
        "disk-guardian",
        "process-manager",
        "memory-watchdog",
        "network-monitor",
        "update-manager",
        "dev-quickstart"
    )
    foreach ($skill in $skillNames) {
        $skillUrl = "$REPO_URL/skills/$skill.md"
        $skillDir = if (Test-Path $SKILLS_DIR) { $SKILLS_DIR } else { "$targetDir\skills" }
        if (Download-File $skillUrl "$skillDir\$skill.md") {
            Write-Info "    Skill: $skill.md"
        }
    }

    # Download dashboard
    if (-not $SkipDashboard) {
        $dashboardFiles = @("index.html", "server.py")
        foreach ($df in $dashboardFiles) {
            $dfUrl = "$REPO_URL/src/Dashboard/$df"
            if (Download-File $dfUrl "$targetDir\Dashboard\$df") {
                Write-Info "    Dashboard: $df"
            }
        }
        Write-Good "Dashboard files installed"
    }

    # Download config
    $configUrl = "$REPO_URL/config/hermes-config.yaml"
    $configDir = "$env:LOCALAPPDATA\hermes"
    Ensure-Directory $configDir
    if (Download-File $configUrl "$configDir\config.yaml") {
        Write-Good "Hermes config updated"
    }

    # ── Set up service (scheduled task) ──
    if (-not $UserMode -and $isAdmin) {
        Write-Step "Setting up Hermes Agent as system service"
        & powershell -ExecutionPolicy Bypass -File "$targetDir\install-service.ps1" -HermesDir $HERMES_DIR -TargetDir $targetDir
        Write-Good "Scheduled task '$TASK_NAME' created — starts at boot as SYSTEM"
    } else {
        Write-Info "Skipping system service (UserMode or non-admin)."
        Write-Info "Hermes will start manually or via Startup folder."
        
        # Add to current user's startup
        $startupFolder = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
        $startupLink = "$startupFolder\HermesAgent.lnk"
        $hermesBin = "$HERMES_DIR\hermes-agent\Scripts\hermes.exe"
        if (Test-Path $hermesBin) {
            $shell = New-Object -ComObject WScript.Shell
            $shortcut = $shell.CreateShortcut($startupLink)
            $shortcut.TargetPath = $hermesBin
            $shortcut.Arguments = "run"
            $shortcut.WorkingDirectory = "$env:LOCALAPPDATA\hermes"
            $shortcut.Save()
            Write-Good "Startup shortcut created for current user"
        }
    }

    # ── Set up tray app autostart ──
    Write-Step "Setting up system tray + global hotkey"
    
    $trayCommand = "powershell -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$targetDir\agent-tray.ps1`""
    
    if (-not $UserMode -and $isAdmin) {
        # Write to HKLM for all users
        $regPath = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run"
        try {
            Set-ItemProperty -Path $regPath -Name $HOTKEY_REG_NAME -Value $trayCommand -Force
            Write-Good "Tray app added to HKLM\...\Run (all users)"
        } catch {
            Write-Warn "Could not write to HKLM Run. Trying HKCU..."
            Set-ItemProperty -Path $HOTKEY_REG_PATH -Name $HOTKEY_REG_NAME -Value $trayCommand -Force
            Write-Good "Tray app added to HKCU\...\Run"
        }
    } else {
        Set-ItemProperty -Path $HOTKEY_REG_PATH -Name $HOTKEY_REG_NAME -Value $trayCommand -Force
        Write-Good "Tray app added to HKCU\...\Run"
    }

    # ── PowerShell profile ──
    Write-Step "Configuring PowerShell profile"
    $profilePath = $PROFILE.CurrentUserAllHosts
    $profileDir = Split-Path $profilePath -Parent
    Ensure-Directory $profileDir

    $profileEntry = @"

# ── Agentic Windows ──
# Provides convenient aliases and paths for the agent OS

`$env:HERMES_CONFIG = "$env:LOCALAPPDATA\hermes\config.yaml"
`$env:DASHBOARD_PORT = "$DASHBOARD_PORT"

function agent { hermes `"`$args`" }
function agent-dash { Start-Process "http://localhost:$DASHBOARD_PORT" }

# Quick system commands via agent
function sys-health { hermes run skill system-health }
function sys-disk { hermes run skill disk-guardian }
function sys-process { hermes run skill process-manager }

Write-Host "⚡ Agentic Windows active. Try: agent, sys-health, agent-dash" -ForegroundColor Cyan
# ── End Agentic Windows ──

"@

    $profileContent = Get-Content $profilePath -ErrorAction SilentlyContinue -Raw
    if ($profileContent -notmatch "Agentic Windows") {
        Add-Content -Path $profilePath -Value $profileEntry
        Write-Good "PowerShell profile updated with agent aliases"
    } else {
        Write-Info "PowerShell profile already has Agentic Windows entries"
    }

    # ── Final steps ──
    Write-Step "Finalizing installation"

    # Try to start the tray app immediately
    # (If running as admin, the tray runs with admin privileges — acceptable for v1)
    try {
        Start-Process -WindowStyle Hidden -FilePath "powershell" `
            -ArgumentList "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$targetDir\agent-tray.ps1`""
        Write-Good "Agent tray app started"
    } catch {
        Write-Info "Tray app will start on next login (configured in registry autostart)"
    }

    # ── Summary ──
    Write-Host ""
    Write-Host "  ╔══════════════════════════════════════════╗" -ForegroundColor $C_GOOD
    Write-Host "  ║    ✅  AGENTIC WINDOWS INSTALLED!       ║" -ForegroundColor $C_GOOD
    Write-Host "  ╚══════════════════════════════════════════╝" -ForegroundColor $C_GOOD
    Write-Host ""
    Write-Host "  Press Win+Space to invoke the agent from anywhere" -ForegroundColor $C_INFO
    Write-Host "  Open dashboard: http://localhost:$DASHBOARD_PORT" -ForegroundColor $C_INFO
    Write-Host "  Try: sys-health, sys-disk, sys-process in PowerShell" -ForegroundColor $C_INFO
    Write-Host "  Ask agent: 'How is my system doing?'" -ForegroundColor $C_INFO
    Write-Host ""
    Write-Host "  Restart your PC to start the agent service." -ForegroundColor $C_WARN
    Write-Host "  Run '.\install.ps1 -Uninstall' to remove everything." -ForegroundColor $C_WARN
    Write-Host ""
}

# ──────────────────────────────────────────────
# Uninstallation logic
# ──────────────────────────────────────────────

function Uninstall-AgenticWindows {
    Write-Host "`n"
    Write-Host "  ╔══════════════════════════════════════════╗" -ForegroundColor $C_WARN
    Write-Host "  ║     🗑️  AGENTIC WINDOWS UNINSTALL        ║" -ForegroundColor $C_WARN
    Write-Host "  ╚══════════════════════════════════════════╝" -ForegroundColor $C_WARN
    Write-Host ""

    if (-not $Force) {
        $confirm = Read-Host "  This will remove all Agentic Windows components. Continue? (y/N)"
        if ($confirm -ne "y") { Write-Info "Uninstall cancelled."; return }
    }

    # Remove scheduled task
    $taskExists = Get-ScheduledTask -TaskName $TASK_NAME -ErrorAction SilentlyContinue
    if ($taskExists) {
        Unregister-ScheduledTask -TaskName $TASK_NAME -Confirm:$false
        Write-Good "Removed scheduled task '$TASK_NAME'"
    }

    # Remove tray app from startup
    $regPaths = @(
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
    )
    foreach ($rp in $regPaths) {
        if (Test-Path $rp) {
            $val = Get-ItemProperty -Path $rp -Name $HOTKEY_REG_NAME -ErrorAction SilentlyContinue
            if ($val) {
                Remove-ItemProperty -Path $rp -Name $HOTKEY_REG_NAME -Force -ErrorAction SilentlyContinue
                Write-Good "Removed tray app from registry startup ($rp)"
            }
        }
    }

    # Kill running processes
    $processes = @("powershell", "hermes")
    foreach ($p in $processes) {
        $found = Get-Process -Name $p -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like "*agent-tray*" -or $_.CommandLine -like "*HermesAgent*" }
        if ($found) {
            $found | Stop-Process -Force -ErrorAction SilentlyContinue
            Write-Info "Stopped process: $p"
        }
    }

    # Remove files
    $paths = @()
    if (Test-Path $AGENTIC_DIR) { $paths += $AGENTIC_DIR }
    if (Test-Path $AGENTIC_DIR_USER) { $paths += $AGENTIC_DIR_USER }

    foreach ($p in $paths) {
        try {
            Remove-Item -Path $p -Recurse -Force -ErrorAction Stop
            Write-Good "Removed: $p"
        } catch {
            Write-Warn "Could not remove: $p ($($_.Exception.Message))"
        }
    }

    # Restore PowerShell profile
    $profilePath = $PROFILE.CurrentUserAllHosts
    if (Test-Path $profilePath) {
        $content = Get-Content $profilePath -Raw
        if ($content -match "(?s)── Agentic Windows ──.*── End Agentic Windows ──") {
            $content = $content -replace "(?s)`n# ── Agentic Windows ──.*?── End Agentic Windows ──`n", ""
            Set-Content -Path $profilePath -Value $content -Force
            Write-Good "PowerShell profile cleaned"
        }
    }

    Write-Host ""
    Write-Host "  ✅ Agentic Windows has been uninstalled." -ForegroundColor $C_GOOD
    Write-Host "  Hermes Agent and dev tools remain installed on your system." -ForegroundColor $C_INFO
    Write-Host "  Remove them separately if desired." -ForegroundColor $C_INFO
    Write-Host ""
}

# ──────────────────────────────────────────────
# Entry point
# ──────────────────────────────────────────────

if ($Uninstall) {
    Uninstall-AgenticWindows
} elseif ($Install) {
    Install-AgenticWindows
} else {
    Write-Host "`n  Usage: powershell -ExecutionPolicy Bypass -File install.ps1 [-Install | -Uninstall] [-UserMode] [-SkipTools] [-SkipDashboard] [-Force]`n"
}

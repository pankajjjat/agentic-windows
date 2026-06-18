# Architecture Guide

## Overview

Agentic Windows transforms a standard Windows 11 installation into an agent-driven operating system through multiple layers of integration.

## Layer Architecture

```
┌───────────────────────────────────────────────────────────────┐
│                        USER INTERFACE                          │
│  ┌────────────┐  ┌─────────────┐  ┌───────────────────────┐   │
│  │ Dashboard  │  │ System Tray │  │ Agent Overlay         │   │
│  │ (Web UI)   │  │ (Win+Space) │  │ (Voice + Chat)        │   │
│  └─────┬──────┘  └──────┬──────┘  └──────────┬────────────┘   │
├────────┼─────────────────┼────────────────────┼────────────────┤
│        │         USER MODE (ring 3)           │                │
│  ┌─────▼─────────────────▼────────────────────▼────────────┐   │
│  │              Hermes Agent Service                        │   │
│  │  • Runs as SYSTEM at boot                                │   │
│  │  • Start Hermes engine daemon                            │   │
│  │  • Hosts REST API for dashboard                          │   │
│  │  • Self-healing: auto-restarts on crash                  │   │
│  └──────────────────────┬───────────────────────────────────┘   │
│                         │                                        │
│  ┌──────────────────────▼───────────────────────────────────┐   │
│  │             Hermes Agent Engine (CLI)                    │   │
│  │  • Core agent runtime                                    │   │
│  │  • LLM inference                                         │   │
│  │  • Memory/skills system                                  │   │
│  │  • Tool execution                                        │   │
│  └──────────────────────┬───────────────────────────────────┘   │
├─────────────────────────┼───────────────────────────────────────┤
│                  KERNEL MODE (ring 0)                            │
│  ┌──────────────────────▼───────────────────────────────────┐   │
│  │  HermesCore.sys (optional — requires WDK)                │   │
│  │  • Process/thread notifications (PsSetCreateProcess)     │   │
│  │  • Image load notifications                               │   │
│  │  • IOCTL interface → user-mode agent                     │   │
│  │  • System event awareness                                 │   │
│  └──────────────────────────────────────────────────────────┘   │
└───────────────────────────────────────────────────────────────┘
```

## Component Architecture

### 1. Hermes Agent (The Brain)

The core Hermes Agent engine handles all intelligence:
- Natural language understanding and generation
- Tool invocation (skills, web, terminal, etc.)
- Memory persistence across sessions
- Skill loading and execution

**Location**: `~/.hermes/hermes-agent/`
**CLI**: `hermes run` starts the daemon

### 2. Agent Service (The Heartbeat)

A scheduled task running as SYSTEM ensures the agent is always available:
- Registered as `HermesAgentService` in Task Scheduler
- Starts at boot, before any user logs in
- Runs `agent-startup.ps1` which launches Hermes + dashboard
- Self-healing: monitors processes and restarts on crash

**Location**: `C:\Program Files\AgenticWindows\agent-startup.ps1`

### 3. Agentic Dashboard (The Face)

A web-based UI for system management and agent interaction:
- Zero-dependency Python HTTP server
- Live system stats (CPU, RAM, disk, processes)
- Agent chat interface
- Quick-action buttons for common tasks
- Skill browser

**Location**: `C:\Program Files\AgenticWindows\Dashboard\`
**URL**: `http://localhost:4775`

### 4. System Tray + Hotkey (Quick Access)

A PowerShell-based tray app for instant agent access:
- System tray icon with context menu
- Win+Space global hotkey
- Quick input dialog for agent commands
- Dashboard and health check shortcuts

**Location**: `C:\Program Files\AgenticWindows\agent-tray.ps1`

### 5. Pre-Loaded Skills (Tools)

Hermes skills for system management:
- `system-health`: Full system diagnostic
- `disk-guardian`: Disk cleanup and monitoring
- `process-manager`: Process list and control
- `memory-watchdog`: Memory leak detection
- `network-monitor`: Network diagnostics
- `update-manager`: Windows Update management
- `dev-quickstart`: Dev environment setup

**Location**: `~/.hermes/skills/`

### 6. Kernel Driver (Optional — Deep Integration)

HermesCore.sys provides kernel-level awareness:
- Process creation/termination notifications
- Thread creation/termination notifications
- Image (DLL/exe) load notifications
- IOCTL communication with user-mode agent

**Location**: `C:\Windows\System32\drivers\hermes_core.sys`

## Data Flow

### User → Agent → Action

```
User types "Free up disk space"
       │
       ▼
System Tray / Dashboard / Terminal
       │
       ▼ (HTTP or CLI)
Hermes Agent Service
       │
       ├─► Loads disk-guardian skill
       ├─► Executes PowerShell cleanup commands
       ├─► Collects results
       └─► Returns formatted response
       │
       ▼
User sees: "🧹 Cleaned 1.2GB from temp files..."
```

### System → Agent (Proactive)

```
Kernel Driver detects:
  - New process launched
  - Memory usage spike
  - Registry change
       │
       ▼ (IOCTL / named pipe)
Hermes Agent Service
       │
       ├─► Evaluates if action needed
       ├─► Alerts user if threshold exceeded
       └─► Auto-remediates if configured
```

## Communication Interfaces

| Interface | Protocol | Port/Socket | Used By |
|-----------|----------|-------------|---------|
| Dashboard HTTP | HTTP REST | localhost:4775 | Browser, Tray |
| Hermes API | HTTP | localhost:4774 | Hermes internal |
| Hermes CLI | stdin/stdout | — | PowerShell |
| Kernel IOCTL | DeviceIoControl | \\.\HermesCore | Python/C# agent |
| System tray | Named pipe (future) | — | Tray ↔ Service |

## Security Boundaries

1. **Service runs as SYSTEM** — highest user-mode privilege, required for system management
2. **Dashboard is localhost only** — not exposed to the network
3. **Kernel driver requires testsigning** — explicit user action to enable
4. **Hermes API key** — stored locally, never transmitted
5. **All code is open-source** — auditable by anyone

## Deployment Targets

| Mode | Admin Required | Features |
|------|---------------|----------|
| **System-wide** | Yes | Service, hotkey, dashboard, kernel driver |
| **User-mode** | No | Agent, skills, startup shortcut |

## Dependency Graph

```
install.ps1
    ├── Downloads Hermes Agent (official)
    ├── Downloads OpenCode (npm)
    ├── Creates scheduled task
    │   └── agent-startup.ps1
    │       ├── Starts hermes daemon
    │       └── Starts dashboard server (server.py)
    ├── Installs tray app (auto-start registry)
    │   └── agent-tray.ps1
    │       ├── Win+Space hotkey
    │       ├── System tray icon
    │       └── Quick input dialog → hermes CLI
    ├── Installs skills to ~/.hermes/skills/
    ├── Updates PowerShell profile
    └── Updates Hermes config
```

## CI/CD Pipeline

```
.github/workflows/
├── build-driver.yml   # Auto-builds HermesCore.sys on every release
│                      # Uses WDK via GitHub Actions (Windows 2022)
│                      # Uploads HermesCore-x64 artifact
│                      # Optional: code-sign with DRIVER_SIGNING_PFX secret
└── validate.yml       # Validates install.ps1 + Python syntax on every push
```

The kernel driver is **automatically built by CI** — users download a pre-compiled
`HermesCore.sys` from the Releases page. No WDK installation needed.

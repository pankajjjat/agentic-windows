# ⚡ Agentic Windows

**Transform any Windows 11 installation into an AI-native, agent-driven operating system — without reinstalling.**

Agentic Windows embeds [Hermes Agent](https://hermes-agent.nousresearch.com) and [OpenCode](https://github.com/opencode-ai/opencode) into your OS at the system level, giving you:

- 🤖 **AI Agent as OS component** — runs as a Windows service, available 24/7
- 🎤 **Voice + text control** — talk to your PC naturally
- 🔔 **Win+Space instant agent** — invoke the agent from anywhere with a global hotkey
- 📊 **Live system dashboard** — monitor health, manage processes, control your PC
- 🩺 **Self-healing OS** — automatic disk cleanup, memory management, proactive health
- 🛡️ **Kernel-level awareness** (optional) — HermesCore.sys monitors system activity
- 🧠 **Pre-loaded skills** — system management, dev workflows, automation
- 🔧 **Zero config** — one PowerShell script installs everything

---

## 🚀 Quick Install

**Run ONE command in PowerShell as Administrator:**

```powershell
iex "& { $(irm https://raw.githubusercontent.com/pankajjjat/agentic-windows/main/install.ps1) } -Install"
```

Or download and run locally:

```powershell
# Download
irm https://raw.githubusercontent.com/pankajjjat/agentic-windows/main/install.ps1 -OutFile install.ps1

# Run as Administrator
powershell -ExecutionPolicy Bypass -File install.ps1 -Install
```

> **Requirements**: Windows 11 (22H2+), 8GB RAM, 5GB free disk, Administrator access.

---

## ✨ What You Get

### 🧬 System Integration

| Feature | How it works |
|---------|-------------|
| **Hermes as SYSTEM Service** | Starts at boot, runs as LocalSystem, always available |
| **Global Hotkey** | `Win+Space` anywhere invokes the agent overlay |
| **System Tray** | Agent icon in system tray — quick access, status info |
| **PowerShell Profile** | `hermes` command available in every terminal |
| **Scheduled Health Checks** | Cron jobs for disk, memory, network, updates |
| **Kernel Driver** (optional) | Process/thread monitoring via kernel callbacks |

### 🖥️ Agentic Dashboard

A web-based dashboard accessible at `http://localhost:4774`:

```
┌──────────────────────────────────────────────────────────────┐
│  ⚡ AGENTIC WINDOWS  ●  System: Healthy  ●  3:42 PM         │
├──────────────────────────────────────────────────────────────┤
│  ┌──────────────────────────────────────────────────────┐    │
│  │  [Ask the agent anything...]                     ▶️  │    │
│  └──────────────────────────────────────────────────────┘    │
│                                                              │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐    │
│  │ System   │  │ Process  │  │   Disk   │  │ Network  │    │
│  │ CPU 23%  │  │  42 apps │  │ C: 45%   │  │ UP 2h    │    │
│  │ RAM 3.2G │  │ Chrome   │  │ D: 12%   │  │ IP 192…  │    │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘    │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐    │
│  │   ████████████████░░░░░░░░░░  45% — C:\  (89/200GB) │    │
│  │   ████░░░░░░░░░░░░░░░░░░░░░  12% — D:\  (12/100GB) │    │
│  └──────────────────────────────────────────────────────┘    │
│                                                              │
│  [🛡 Health Check] [🧹 Clean Disk] [⚡ Quick Actions ▼]    │
└──────────────────────────────────────────────────────────────┘
```

### 🧠 Pre-Loaded Hermes Skills

| Skill | What it does |
|-------|-------------|
| `system-health` | CPU, RAM, disk, temps, uptime — "How's my PC doing?" |
| `disk-guardian` | Monitors free space, auto-cleans temp/cache when low |
| `process-manager` | List, kill, prioritize processes — "Kill Chrome" |
| `memory-watchdog` | Detects leaks, clears standby memory |
| `network-monitor` | IP info, connection stats, DNS flush |
| `update-manager` | Check/install Windows updates via agent |
| `dev-quickstart` | Scaffold projects, install dev tooling |

### 🛠️ Developer Toolchain (Optional)

Pre-configured and ready:

| Tool | How it's set up |
|------|----------------|
| **Python 3.x** | On PATH, with uv package manager |
| **Node.js + npm** | Latest LTS, on PATH |
| **Git** | With credential helper, sensible defaults |
| **VS Code** | `code` CLI in PATH |
| **Windows Terminal** | Custom profile with agent theme |
| **OpenCode** | `opencode` CLI globally available |
| **Everything Search** | Replaces Windows Search (instant results) |

---

## 🏗️ Architecture

```
┌────────────────────────────────────────────────────────────┐
│                    AGENTIC WINDOWS                           │
├────────────────────────────────────────────────────────────┤
│                                                            │
│  ┌─ KERNEL MODE (optional, ring 0) ─────────────────────┐ │
│  │  HermesCore.sys                                       │ │
│  │  └─ Process/thread/image load notifications           │ │
│  │  └─ Registry change monitoring                        │ │
│  │  └─ IOCTL → user-mode agent communication             │ │
│  └───────────────────────────────────────────────────────┘ │
│                                                            │
│  ┌─ SYSTEM SERVICES (ring 3) ────────────────────────────┐ │
│  │  Hermes Agent (LocalSystem)                            │ │
│  │  └─ Started at boot via Task Scheduler                 │ │
│  │  └─ Persists across user sessions                      │ │
│  │  └─ Exposes API at localhost:4774                      │ │
│  └───────────────────────────────────────────────────────┘ │
│                                                            │
│  ┌─ USER SPACE ──────────────────────────────────────────┐ │
│  │  Agent Tray App (Win+Space, system tray)              │ │
│  │  Agentic Dashboard (web UI at localhost:4774)          │ │
│  │  Hermes CLI in PowerShell / Terminal                   │ │
│  │  Pre-loaded skills in ~/.hermes/skills/                │ │
│  └───────────────────────────────────────────────────────┘ │
│                                                            │
└────────────────────────────────────────────────────────────┘
```

---

## 📦 What Gets Installed

```
C:\Program Files\AgenticWindows\
├── agent-tray.ps1          # System tray + global hotkey app
├── install-service.ps1     # Task scheduler registration
├── agent-startup.ps1       # Hermes boot-time launcher
├── Dashboard\              # Web dashboard files
└── skills\                 # Pre-loaded Hermes skills

C:\Users\<you>\AppData\Local\hermes\
├── hermes-agent\            # Hermes Agent installation
├── skills\                  # + our pre-loaded skills
└── config.yaml              # Hermes config (modified)

Windows Task Scheduler:
└─ HermesAgentService        # Starts at boot as SYSTEM

Global hotkey:
└─ Win+Space                 # Invokes agent overlay
```

---

## 🎮 Usage

### Basic Commands

| Action | How |
|--------|-----|
| **Invoke agent** | Press `Win+Space` anywhere |
| **Voice command** | Click 🎤 in dashboard or say "Hey Agent" (if enabled) |
| **Open dashboard** | `http://localhost:4774` in browser |
| **Terminal agent** | Type `hermes` in PowerShell/CMD |
| **System health** | Ask agent: "Check my system health" |
| **Clean disk** | Ask agent: "Free up disk space" |
| **Manage updates** | Ask agent: "Check for updates" |

### Agent Commands (try these)

- "How is my system doing?"
- "Show me running processes sorted by RAM"
- "Free up 10GB of disk space"
- "Kill all Chrome processes"
- "Check for Windows updates"
- "What's my IP address?"
- "Create a new React project called my-app"
- "Open VS Code with my last project"
- "Install Node.js 22" (if not present)
- "Run a health check"

### Hermes Skills for System Management

```
hermes> Run the disk-guardian skill
hermes> Run the system-health skill
hermes> Run the memory-watchdog skill
hermes> Run the network-monitor skill
hermes> Run the update-manager skill
hermes> Run the process-manager skill
```

---

## ⚙️ Configuration

### Hermes Config (`~/.hermes/config.yaml`)

The installer adds Windows-specific configuration:

```yaml
provider: openrouter
model: nousresearch/hermes-3-sonnet
skills:
  enabled:
    - system-health
    - disk-guardian
    - process-manager
    - memory-watchdog
    - network-monitor
    - update-manager
    - dev-quickstart
memory:
  enabled: true
  cross_session: true
services:
  dashboard_port: 4774
  auto_start: true
```

Edit this file anytime — the agent reads it on restart.

---

## 🧪 Testing Mode: Install without Admin Rights

```powershell
.\install.ps1 -UserMode
```

This installs everything per-user (no admin needed), minus the system service and kernel driver.

---

## 🗑️ Uninstall

**One command as Administrator:**

```powershell
.\install.ps1 -Uninstall
```

This removes:
- Scheduled task
- Global hotkey
- Dashboard files
- Agent tray app
- System tray icon auto-start
- Restores original PowerShell profile

It does **NOT** remove Hermes itself (`hermes` command remains available) — remove that separately with `hermes uninstall`.

---

## 🔬 Kernel Driver (Advanced)

The kernel driver `HermesCore.sys` enables deep OS integration:

- Real-time process/thread creation monitoring
- Registry change callbacks
- System event notifications piped to Hermes

**Building requires**: Windows Driver Kit (WDK) + Visual Studio.

```powershell
# Prerequisites (one-time)
winget install "Windows Driver Kit" -s msstore

# Build
cd src\KernelDriver
build.bat

# Install (from admin prompt)
sc create HermesCore type= kernel binPath= "C:\Program Files\AgenticWindows\HermesCore.sys"
sc start HermesCore
```

> ⚠️ The kernel driver requires test-signing mode enabled. The installer can do this for you:
> `bcdedit /set testsigning on`

---

## 📁 Repository Structure

```
agentic-windows/
├── README.md                 # This file
├── LICENSE                   # MIT License
├── install.ps1               # One-command installer
├── uninstall.ps1             # Clean removal
├── src/
│   ├── AgentService/         # System service components
│   ├── AgentTray/            # Tray app + global hotkey
│   ├── Dashboard/            # Web dashboard
│   └── KernelDriver/         # Kernel driver (WDK)
├── skills/                   # Pre-loaded Hermes skills
├── config/                   # Configuration files
└── docs/                     # Documentation
```

---

## 🔒 Security

- The agent service runs as **LocalSystem** — same as other Windows services
- Kernel driver requires explicit permission via `bcdedit /set testsigning on`
- All communication is **localhost-only** (not exposed to network)
- The installer does NOT collect any telemetry or user data
- Hermes requires your API key — it's stored locally, never sent elsewhere
- Review the source — everything is open

---

## 🧰 Requirements

| Requirement | Minimum | Recommended |
|------------|---------|-------------|
| OS | Windows 11 22H2 (build 22621+) | Windows 11 24H2+ |
| RAM | 8 GB | 16 GB+ |
| Disk | 5 GB free | 10 GB+ free |
| Admin | Required for service install | Always run as admin |
| Hermes | Installed automatically | — |
| Network | Internet (first install only) | Internet (API access) |

---

## 🛣️ Roadmap

- [x] Hermes as boot-time SYSTEM service
- [x] Global hotkey + system tray integration
- [x] Web-based agentic dashboard
- [x] Pre-loaded system management skills
- [x] One-command installer
- [ ] Kernel driver (HermesCore.sys) — process monitoring
- [ ] Custom credential provider — agent on login screen
- [ ] Voice wake word ("Hey Agent")
- [ ] Agent shell replacement (explorer.exe alternative)
- [ ] One-click AI provider setup wizard
- [ ] Integrated terminal with agent sidebar

---

## 🤝 Contributing

PRs welcome! Focus areas:

- New Hermes skills for system management
- Dashboard UI improvements
- Kernel driver stability
- Localization / multi-language support
- Better service failure recovery

---

## 📄 License

MIT — do whatever you want with it.

---

## 🙏 Credits

- [Hermes Agent](https://hermes-agent.nousresearch.com) by Nous Research — the brain
- [OpenCode](https://github.com/opencode-ai/opencode) — coding agent integration
- [NSSM](https://nssm.cc) — service wrapper inspiration (though we use native Task Scheduler)

---

**Made by [Pankaj](https://github.com/pankajjjat) — because Windows should work for you, not against you.**

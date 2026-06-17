# Getting Started with Agentic Windows

## Quick Install

### One-Command Installer

Open **PowerShell as Administrator** and run:

```powershell
iex "& { $(irm https://raw.githubusercontent.com/pankajjjat/agentic-windows/main/install.ps1) } -Install"
```

This single command:
1. Installs Hermes Agent (if not already installed)
2. Installs OpenCode Agent
3. Sets up Hermes as a system service (boot-time)
4. Installs the Agentic Dashboard
5. Configures the Win+Space global hotkey
6. Loads 7 system-management skills
7. Updates your PowerShell profile with agent aliases

### Step-by-Step Manual Install

If you prefer to understand what happens:

```powershell
# 1. Install Hermes Agent
iex (irm https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.ps1)

# 2. Install OpenCode
npm install -g opencode-ai

# 3. Download Agentic Windows
cd ~\Downloads
git clone https://github.com/pankajjjat/agentic-windows.git
cd agentic-windows

# 4. Run installer
.\install.ps1 -Install -Force
```

## First Steps After Install

### 1. Restart Your PC

The agent service starts at boot. After restart:

- ✅ Hermes Agent is running as a system service
- ✅ Dashboard server is running on http://localhost:4775
- ✅ System tray icon with Win+Space hotkey is active

### 2. Open the Dashboard

Open your browser to **http://localhost:4775**

You'll see:
- Live CPU, RAM, disk, and uptime stats
- Quick action buttons (Health Check, Clean Disk, etc.)
- An agent chat interface (if Hermes is configured)
- Process list

### 3. Try the Hotkey

Press **Win+Space** anywhere — a dialog appears where you can ask the agent anything.

### 4. Talk to Your Agent

**From the dashboard** — type in the chat box on the "Agent Chat" tab
**From the hotkey dialog** — press Win+Space, type your command
**From PowerShell** — type `hermes "your question"`

Try these:
- "How is my system doing?"
- "Show me running processes"
- "Free up disk space"
- "Check for updates"
- "What's my IP address?"

### 5. Use System Management Skills

The agent has pre-loaded skills for system tasks:

```powershell
# Run a system health check
hermes run skill system-health

# Run disk cleanup
hermes run skill disk-guardian

# List top processes
hermes run skill process-manager

# Check memory status
hermes run skill memory-watchdog

# Network diagnostics
hermes run skill network-monitor

# Check Windows updates
hermes run skill update-manager

# Check dev tools
hermes run skill dev-quickstart
```

Or in the dashboard, click the skill cards or use the quick action buttons.

## Configuring Your AI Provider

Hermes needs an AI provider to work. Configure one:

```powershell
# Option 1: OpenRouter (recommended — multi-model access)
hermes config set provider openrouter
hermes config set model nousresearch/hermes-3-sonnet
# Set your API key:
# Create ~/.hermes/config.yaml and add:
# provider_config:
#   openrouter:
#     api_key: "sk-or-v1-..."

# Option 2: OpenAI
hermes config set provider openai
hermes config set model gpt-4o

# Option 3: Anthropic
hermes config set provider anthropic
hermes config set model claude-sonnet-4
```

## PowerShell Aliases

After install, your PowerShell profile has these new commands:

| Command | What it does |
|---------|-------------|
| `agent <cmd>` | Shorthand for `hermes <cmd>` |
| `dash` | Opens the dashboard in browser |
| `sys-health` | Runs system health skill |
| `sys-disk` | Runs disk guardian skill |
| `sys-process` | Runs process manager skill |
| `sys-memory` | Runs memory watchdog skill |
| `sys-network` | Runs network monitor skill |
| `sys-updates` | Runs update manager skill |
| `dev-status` | Checks dev tool installations |

## Customizing

### Add More Skills

Skills are markdown files in `~/.hermes/skills/`. You can:
- Edit existing skills to customize behavior
- Add new skills by creating new `.md` files
- Browse community skills from the Hermes docs

### Change Dashboard Port

```powershell
$env:DASHBOARD_PORT = "4775"  # change this
```

### Change Service Behavior

Edit `C:\Program Files\AgenticWindows\agent-startup.ps1` to modify:
- What Hermes flags are used
- When health checks run

## Troubleshooting

### Dashboard shows "offline"
1. Check if the Python server is running: `tasklist | findstr python`
2. Restart the service: `Start-ScheduledTask -TaskName HermesAgentService`
3. Check logs: `C:\Program Files\AgenticWindows\logs\`

### Win+Space doesn't work
1. Right-click the tray icon → Exit, then run:
   ```powershell
   powershell -WindowStyle Hidden -File "C:\Program Files\AgenticWindows\agent-tray.ps1"
   ```
2. The tray app runs at startup via registry `HKCU\...\Run\AgenticWindowsTray`

### Hermes agent doesn't respond
1. Ensure API key is configured: `hermes config show`
2. Check: `hermes run` in PowerShell
3. Verify the service: `Get-ScheduledTask -TaskName HermesAgentService`

### Can't install without admin rights
Run: `.\install.ps1 -Install -UserMode`
This installs everything per-user (agent only, no system service or kernel driver).

## Uninstall

```powershell
# Run as Administrator
.\install.ps1 -Uninstall
```

This removes all Agentic Windows components but leaves Hermes installed.

## Next Steps

- ⚡ [Explore the code](https://github.com/pankajjjat/agentic-windows) — contribute, report issues, suggest features
- 🧠 [Learn about Hermes skills](https://hermes-agent.nousresearch.com/docs/user-guide/features/skills) — create your own
- 🔬 [Build the kernel driver](src/KernelDriver/build.md) — enable deep OS integration
- 🛠️ [Review the architecture](docs/architecture.md) — understand how it all works

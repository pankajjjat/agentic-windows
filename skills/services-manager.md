---
name: services-manager
description: "Manage Windows services — list, start, stop, restart, and diagnose services"
trigger: "Windows service management, service status, start/stop/restart services"
---

# Services Manager

Manage Windows services: list running services, start/stop/restart, view dependencies, and diagnose failures.

## Usage

```
User: "List all running services"
Agent: runs services-manager

User: "Restart the print spooler"
Agent: runs services-manager with action=restart, service=Spooler

User: "What services are set to auto-start but stopped?"
Agent: runs services-manager with action=list-auto-stopped
```

## Parameters (via hermes config)

| Parameter | Description | Default |
|-----------|-------------|---------|
| `action`  | `list`, `start`, `stop`, `restart`, `status`, `list-auto-stopped`, `list-failed` | `list` |
| `service` | Service name (e.g. `Spooler`, `wuauserv`) | (all) |

## PowerShell Commands

### List services

```powershell
# List all services
Get-Service | Select-Object Name, DisplayName, Status, StartType | Format-Table -AutoSize

# Auto-start services that are stopped
Get-Service | Where-Object { $_.StartType -eq 'Automatic' -and $_.Status -eq 'Stopped' } |
  Select-Object Name, DisplayName | Format-Table -AutoSize

# Failed services (recent Event Log)
Get-WinEvent -LogName System -MaxEvents 50 |
  Where-Object { $_.Id -eq 7034 -or $_.Id -eq 7031 } |
  Format-Table TimeCreated, Message -AutoSize -Wrap
```

### Start/Stop/Restart

```powershell
# Start a service
Start-Service -Name Spooler

# Stop a service
Stop-Service -Name WSearch -Force

# Restart (with status check)
Restart-Service -Name WlanSvc -Force
Start-Sleep 2
Get-Service WlanSvc | Select-Object Name, Status

# Safe restart with delay
Stop-Service -Name Spooler -ErrorAction SilentlyContinue
Start-Sleep 1
Start-Service -Name Spooler
Start-Sleep 1
Get-Service Spooler | Select-Object Name, Status
```

### Service dependencies

```powershell
# What does this service depend on?
Get-Service -Name Spooler -DependentServices | Format-Table Name, Status

# What needs this service to run?
Get-Service -Name Spooler -RequiredServices | Format-Table Name, Status
```

### Change service start type

```powershell
# Set to automatic
Set-Service -Name WSearch -StartupType Automatic

# Set to manual (delayed start)
Set-Service -Name WSearch -StartupType Manual

# Disable
Set-Service -Name WSearch -StartupType Disabled
```

## Troubleshooting

### Service won't start

```powershell
# Check status + error details
Get-Service -Name <Name> | Select-Object *

# Check recent Event Log for service errors
Get-WinEvent -LogName System -MaxEvents 20 |
  Where-Object { $_.LevelDisplayName -eq 'Error' -and $_.ProviderName -like '*Service*' } |
  Format-Table TimeCreated, Id, Message -AutoSize -Wrap
```

### Service hangs

```powershell
# Kill the underlying process
$pid = (Get-CimInstance Win32_Service -Filter "Name='<Name>'").ProcessId
if ($pid -gt 0) { Stop-Process -Id $pid -Force }
# Then reset service state
sc.exe query <Name>
sc.exe queryex <Name>
```

### Reset service to default

```powershell
# sc.exe sdshow <Name> — view security descriptor
# sc.exe sdset <Name> <SDDL> — restore to default

# Reset to Microsoft default (common services)
# wuauserv (Windows Update)
sc.exe config wuauserv binPath="C:\Windows\System32\svchost.exe -k netsvcs -p"
sc.exe config wuauserv start= delayed-auto
```

## Examples

```
User: "What services failed recently?"
User: "Start the Windows Update service"
User: "Stop the search indexer to free CPU"
User: "List services that are set to auto but not running"
User: "Restart all networking services"
User: "Show me what depends on the Print Spooler"
User: "Disable Xbox Game Bar services"
```

## Related

- `system-health` — full system diagnostic
- `process-manager` — process-level management

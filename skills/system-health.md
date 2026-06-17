---
name: system-health
description: Comprehensive system health check — CPU, RAM, disk, network, and uptime status
version: 1.0
author: Agentic Windows
---

# System Health

## Description
Runs a complete health check on the Windows system, reporting CPU usage, memory utilization, disk space, network status, and system uptime. Identifies potential issues and suggests fixes.

## Triggers
- "How is my system doing?"
- "Check my system health"
- "Run a health check"
- "System status"
- "Is my PC healthy?"

## Steps

1. **CPU Check**
   ```powershell
   $cpu = (Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average
   $cores = (Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors
   if ($cpu -gt 80) { "⚠️ CPU at ${cpu}% — high load. Check for runaway processes." }
   else { "✅ CPU at ${cpu}% (${cores} logical cores) — normal." }
   ```

2. **Memory Check**
   ```powershell
   $os = Get-CimInstance Win32_OperatingSystem
   $total = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
   $free = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
   $used = [math]::Round($total - $free, 1)
   $pct = [math]::Round(($used / $total) * 100, 1)
   if ($pct -gt 85) { "⚠️ RAM: ${used}GB/${total}GB (${pct}%) — high usage." }
   else { "✅ RAM: ${used}GB/${total}GB (${pct}%) — OK." }
   ```

3. **Disk Check**
   ```powershell
   Get-CimInstance Win32_LogicalDisk | Where-Object { $_.DriveType -eq 3 } | ForEach-Object {
     $total = [math]::Round($_.Size / 1GB, 1)
     $free = [math]::Round($_.FreeSpace / 1GB, 1)
     $used = [math]::Round($total - $free, 1)
     $pct = [math]::Round(($used / $total) * 100, 1)
     $status = if ($pct -gt 90) { "⚠️" } elseif ($pct -gt 75) { "⚡" } else { "✅" }
     "${status} $($_.DeviceID): ${used}GB/${total}GB (${pct}%) — ${free}GB free"
   }
   ```

4. **Uptime Check**
   ```powershell
   $boot = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
   $uptime = (Get-Date) - $boot
   "🕐 Uptime: $($uptime.Days)d $($uptime.Hours)h $($uptime.Minutes)m"
   ```

5. **Temperature Check** (if WMI supports it)
   ```powershell
   $temps = Get-CimInstance -Namespace "root/wmi" -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction SilentlyContinue
   if ($temps) { $temps | ForEach-Object { "$($_.InstanceName): $([math]::Round(($_.CurrentTemperature - 2732) / 10, 1))°C" } }
   else { "🌡️ Thermal sensors not available via WMI." }
   ```

6. **Network Check**
   ```powershell
   $adapters = Get-NetAdapter | Where-Object { $_.Status -eq "Up" }
   if ($adapters) { "🌐 Connected via: $($adapters.Count) adapter(s)" }
   else { "⚠️ No active network adapters found." }
   ```

## Output Format

```
╔══════════════════════════════════════════╗
║          SYSTEM HEALTH REPORT            ║
╚══════════════════════════════════════════╝

🖥️ CPU:    [result]
🧠 RAM:    [result]  
💾 DISK:   [result]
🕐 UPTIME: [result]
🌡️ TEMP:   [result]
🌐 NET:    [result]

Issues found: [count]
Recommendations:
  • [if any]
```

## Notes
- Run this daily to stay on top of system health
- The Agentic Windows dashboard refreshes this automatically every 5 seconds
- For deep analysis, combine with `process-manager` and `memory-watchdog` skills

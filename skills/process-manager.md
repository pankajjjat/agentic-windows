---
name: process-manager
description: List, monitor, and manage running processes with agent control
version: 1.0
author: Agentic Windows
---

# Process Manager

## Description
Lists running processes sorted by memory or CPU usage, provides details on resource consumption, and can kill or restart processes by name or PID.

## Triggers
- "Show running processes"
- "What processes are using the most RAM?"
- "Kill [process name]"
- "List top processes"
- "Run process-manager"
- "Is [process] running?"

## Steps

1. **List Top Processes by Memory**
   ```powershell
   Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 20 |
   ForEach-Object {
     $mem = [math]::Round($_.WorkingSet64 / 1MB, 1)
     "{0,-6} {1,-30} {2,8}MB" -f $_.Id, $_.ProcessName, $mem
   }
   ```

2. **List Top Processes by CPU** (last 5 seconds average)
   ```powershell
   Get-Process | Sort-Object CPU -Descending | Select-Object -First 15 |
   ForEach-Object {
     "{0,-6} {1,-30} {2,8}s CPU" -f $_.Id, $_.ProcessName, [math]::Round($_.CPU, 1)
   }
   ```

3. **Check Specific Process**
   ```powershell
   param($ProcessName)
   $procs = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
   if ($procs) {
     $count = $procs.Count
     $totalMem = [math]::Round(($procs | Measure-Object WorkingSet64 -Sum).Sum / 1MB, 1)
     "$ProcessName: $count instance(s), ${totalMem}MB total"
   } else {
     "$ProcessName is not running"
   }
   ```

4. **Kill Process** (requires admin for some processes)
   ```powershell
   param($ProcessName)
   try {
     Get-Process -Name $ProcessName -ErrorAction Stop | Stop-Process -Force
     "✅ Killed all $ProcessName processes"
   } catch {
     "❌ Could not kill $ProcessName: $($_.Exception.Message)"
   }
   ```

5. **Process Count by Category**
   ```powershell
   $all = Get-Process
   "Total processes: $($all.Count)"
   "  🖥️ System: $(($all | Where-Object { $_.SessionId -eq 0 }).Count)"
   "  👤 User: $(($all | Where-Object { $_.SessionId -ne 0 }).Count)"
   "  🌐 Browser: $(($all | Where-Object { $_.ProcessName -match 'chrome|firefox|edge|brave|opera' }).Count)"
   ```

## Process Kill Examples
- "Kill chrome" → kills all Chrome processes
- "Kill notepad" → kills Notepad
- "Kill 4521" → kills PID 4521
- "Kill all browser processes" → kills Chrome, Firefox, Edge

## Output Format

```
╔══════════════════════════════════════════╗
║          PROCESS MANAGER                 ║
╚══════════════════════════════════════════╝

📊 TOP PROCESSES (by memory):
  PID    Name                           Memory
  ───────────────────────────────────────────
  [data]

⚡ TOP PROCESSES (by CPU):
  [data]

📈 SUMMARY:
  Total: X processes
  User:  Y | System: Z
  Browser: W

💡 INSIGHTS:
  • [if a process is using >1GB RAM, flag it]
  • [if >100 processes, suggest investigating]
```

## Notes
- Use with care when killing system processes
- Some protected processes (antimalware, system) cannot be killed
- Combine with `memory-watchdog` for automatic leak detection

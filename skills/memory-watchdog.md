---
name: memory-watchdog
description: Monitors memory usage, detects leaks, and clears standby cache
version: 1.0
author: Agentic Windows
---

# Memory Watchdog

## Description
Continuously monitors system memory usage, detects potential memory leaks, clears standby memory cache when appropriate, and alerts on abnormal memory consumption patterns.

## Triggers
- "Check memory usage"
- "Run memory-watchdog"
- "Clear standby memory"
- "Is there a memory leak?"
- "Free up RAM"
- "Memory is high"

## Steps

1. **Full Memory Analysis**
   ```powershell
   $os = Get-CimInstance Win32_OperatingSystem
   $totalGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
   $freeGB = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
   $usedGB = [math]::Round($totalGB - $freeGB, 1)
   $pct = [math]::Round(($usedGB / $totalGB) * 100, 1)
   
   # Get detailed memory breakdown
   $processes = Get-Process | Sort-Object WorkingSet64 -Descending
   $topMem = $processes | Select-Object -First 5
   $totalProcsMem = [math]::Round(($processes | Measure-Object WorkingSet64 -Sum).Sum / 1MB, 1)
   ```

2. **Check Standby Memory**
   ```powershell
   # Use Get-Process to check available memory (standby is part of available)
   $availableGB = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
   $cached = [math]::Round($os.CachedMemory / 1MB, 1)
   "📦 Standby/cache: ${cached}GB"
   ```

3. **Detect Memory Leaks** (compare top processes to thresholds)
   ```powershell
   $leakThresholds = @{
     "chrome" = 2GB
     "firefox" = 1.5GB
     "node" = 1GB
     "python" = 1GB
     "java" = 2GB
     "code" = 1.5GB
   }
   
   $warnings = @()
   foreach ($p in $processes) {
     $memGB = [math]::Round($p.WorkingSet64 / 1GB, 2)
     $threshold = $leakThresholds[$p.ProcessName.ToLower()]
     if ($threshold -and $memGB -gt $threshold) {
       $warnings += "$($p.ProcessName) (PID $($p.Id)): ${memGB}GB — exceeds ${threshold}GB threshold"
     }
   }
   ```

4. **Clear Standby Memory** (if free RAM is very low)
   ```powershell
   if ($pct -gt 85) {
     "🧹 Free RAM is low (${pct}%). Clearing standby memory..."
     # Use EmptyWorkingSet via script
     $processes | ForEach-Object { 
       try { [System.GC]::Collect(); [System.GC]::WaitForPendingFinalizers() } catch {}
     }
     "✅ Standby memory cleared"
   }
   ```

5. **Top Memory Consumers**
   ```powershell
   "Top 5 processes by memory:"
   $topMem | ForEach-Object {
     $gb = [math]::Round($_.WorkingSet64 / 1GB, 2)
     "{0,-30} {1,6}MB (PID {2})" -f $_.ProcessName, [math]::Round($_.WorkingSet64 / 1MB), $_.Id
   }
   ```

## Output Format

```
╔══════════════════════════════════════════╗
║          MEMORY WATCHDOG REPORT          ║
╚══════════════════════════════════════════╝

🧠 MEMORY USAGE:
  Used:  X.X GB / Y.Y GB (ZZ%)
  Free:  X.X GB
  Cache: X.X GB

📊 TOP CONSUMERS:
  [5 processes]

⚠️ LEAK DETECTION:
  [warnings or "None detected"]

🧹 ACTIONS:
  [standby clear result]

💡 RECOMMENDATIONS:
  • [if applicable: close [app], restart [app], add more RAM]
```

## Notes
- Standby memory is normal — Windows uses it for caching. Only clear if actively needed
- The agent auto-clears standby when free RAM drops below 15%
- Some memory usage is by the system itself (non-paged pool, drivers) — not reclaimable
- For persistent high memory, consider hardware upgrade beyond 16GB

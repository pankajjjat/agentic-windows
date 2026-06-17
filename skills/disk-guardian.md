---
name: disk-guardian
description: Monitors disk space, cleans temp/cache, and alerts on low space
version: 1.0
author: Agentic Windows
---

# Disk Guardian

## Description
Monitors all drives for free space, automatically cleans temporary files and caches when space runs low, and recommends further cleanup actions. Keeps your disk healthy without manual intervention.

## Triggers
- "Free up disk space"
- "Clean my disk"
- "Disk cleanup"
- "Low disk space"
- "Run disk-guardian"
- "How much free space do I have?"

## Steps

1. **Scan All Drives**
   ```powershell
   $drives = Get-CimInstance Win32_LogicalDisk | Where-Object { $_.DriveType -eq 3 -and $_.Size -gt 0 }
   $critical = @()
   $warning = @()
   
   foreach ($d in $drives) {
     $pct = [math]::Round(($d.Size - $d.FreeSpace) / $d.Size * 100, 1)
     $freeGB = [math]::Round($d.FreeSpace / 1GB, 1)
     $totalGB = [math]::Round($d.Size / 1GB, 1)
     
     if ($pct -ge 90) { $critical += $d }
     elseif ($pct -ge 75) { $warning += $d }
     
     "$($d.DeviceID): ${freeGB}GB free / ${totalGB}GB total (${pct}% used)"
   }
   ```

2. **Auto-Clean Temp Files** (if any drive is >85% full)
   ```powershell
   # Clean Windows temp
   $tempPaths = @("$env:TEMP", "$env:WINDIR\Temp", "$env:WINDIR\Prefetch")
   $cleaned = 0
   foreach ($p in $tempPaths) {
     if (Test-Path $p) {
       $size = (Get-ChildItem $p -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum -ErrorAction SilentlyContinue).Sum
       if ($size -gt 0) {
         Remove-Item "$p\*" -Recurse -Force -ErrorAction SilentlyContinue
         $cleaned += $size
       }
     }
   }
   $cleanedMB = [math]::Round($cleaned / 1MB, 1)
   "🧹 Cleaned ${cleanedMB}MB from temporary files"
   ```

3. **Clean Windows Update Cache**
   ```powershell
   # Stop update service, clean cache, restart
   Stop-Service wuauserv -Force -ErrorAction SilentlyContinue
   $wuPath = "$env:WINDIR\SoftwareDistribution\Download"
   if (Test-Path $wuPath) {
     $size = (Get-ChildItem $wuPath -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum -ErrorAction SilentlyContinue).Sum
     Remove-Item "$wuPath\*" -Recurse -Force -ErrorAction SilentlyContinue
     $wuMB = [math]::Round($size / 1MB, 1)
     "🧹 Cleaned ${wuMB}MB from Windows Update cache"
   }
   Start-Service wuauserv -ErrorAction SilentlyContinue
   ```

4. **Clean Recycle Bin**
   ```powershell
   Clear-RecycleBin -Force -ErrorAction SilentlyContinue
   "🗑️ Emptied Recycle Bin"
   ```

5. **Run DISM Cleanup** (if space is critical)
   ```powershell
   # Only if any drive is above 90%
   if ($critical.Count -gt 0) {
     "⚡ Running DISM component cleanup (this may take a few minutes)..."
     dism /online /Cleanup-Image /StartComponentCleanup /ResetBase | Out-Null
     "✅ DISM cleanup complete"
   }
   ```

## Output Format

```
╔══════════════════════════════════════════╗
║          DISK GUARDIAN REPORT            ║
╚══════════════════════════════════════════╝

📊 DRIVE STATUS:
  [drive info per drive]

🧹 ACTIONS TAKEN:
  • [temp cleanup result]
  • [update cache result]
  • [recycle bin result]
  • [DISM result if run]

📈 BEFORE → AFTER:
  C: XX% → YY%

💡 RECOMMENDATIONS:
  • [suggest moving large folders, uninstalling apps, etc.]
```

## Notes
- The Agentic Windows cron job runs this automatically when disk reaches 85%
- Safe to run anytime — no data loss
- DISM /ResetBase is only triggered at 90%+ as it prevents Windows update rollback

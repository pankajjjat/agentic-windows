---
name: update-manager
description: Check, manage, and install Windows updates via the agent
version: 1.0
author: Agentic Windows
---

# Update Manager

## Description
Checks for available Windows updates, reports their status, and can install pending updates. Manages update settings and provides visibility into what Windows Update is doing.

## Triggers
- "Check for Windows updates"
- "Run update-manager"
- "Are there pending updates?"
- "Install updates"
- "Windows Update status"
- "Update manager"

## Steps

1. **Check Update Status**
   ```powershell
   $updateSession = New-Object -ComObject Microsoft.Update.Session
   $updateSearcher = $updateSession.CreateUpdateSearcher()
   $searchResult = $updateSearcher.Search("IsInstalled=0 AND IsHidden=0")
   
   $pendingCount = $searchResult.Updates.Count
   
   if ($pendingCount -eq 0) {
     "✅ No pending updates found. Your system is up to date."
   } else {
     "📦 $pendingCount update(s) available:"
     $searchResult.Updates | ForEach-Object {
       $kb = $_.KBArticleIDs -join ", "
       "  • $($_.Title) [KB$kb] — $($_.IsDownloaded ? 'Downloaded' : 'Not downloaded')"
     }
   }
   ```

2. **Check Last Update Time**
   ```powershell
   $lastUpdate = Get-HotFix | Sort-Object InstalledOn -Descending | Select-Object -First 1
   if ($lastUpdate) {
     "📅 Last update installed: $($lastUpdate.HotFixID) on $($lastUpdate.InstalledOn)"
   }
   ```

3. **Check Update Service Status**
   ```powershell
   $service = Get-Service wuauserv -ErrorAction SilentlyContinue
   if ($service) {
     "🔧 Windows Update service: $($service.Status)"
   }
   ```

4. **Update Settings**
   ```powershell
   $wuau = Get-ItemProperty -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update" -ErrorAction SilentlyContinue
   if ($wuau) {
     $modes = @{2="Notify before download";3="Auto download & notify";4="Auto download & schedule install";5="Auto install & restart"}
     "⚙️ Update mode: $($modes[$wuau.AUOptions])"
   }
   ```

5. **Install Updates** (only if user explicitly asks)
   ```powershell
   # This requires user confirmation — don't auto-install
   param($InstallUpdates)
   if ($InstallUpdates) {
     $downloader = $updateSession.CreateUpdateDownloader()
     $downloader.Updates = $searchResult.Updates
     $downloadResult = $downloader.Download()
     
     $installer = $updateSession.CreateUpdateInstaller()
     $installer.Updates = $searchResult.Updates
     $installResult = $installer.Install()
     
     "Download: $($downloadResult.ResultCode) | Install: $($installResult.ResultCode)"
     if ($installResult.RebootRequired) { "⚠️ Reboot required to complete installation" }
   }
   ```

## Output Format

```
╔══════════════════════════════════════════╗
║          UPDATE MANAGER REPORT           ║
╚══════════════════════════════════════════╝

📦 PENDING UPDATES: X
  [list of updates]

📅 LAST UPDATE: [date]

🔧 UPDATE SERVICE: [status]

⚙️ UPDATE SETTINGS: [mode]

💡 RECOMMENDATIONS:
  • [if pending: install with caution]
  • [if reboot pending: reboot recommended]
```

## Notes
- The agent checks for updates but does NOT auto-install without confirmation
- Some updates require a reboot — the agent will notify you
- The scheduled task `HermesAgentService` should NOT be interrupted during update installation
- See `wuauclt /detectnow` or `usoclient StartScan` for manual trigger

---
name: cleanup-tool
description: "Clean up disk space — temp files, caches, old updates, Recycle Bin, and large files"
trigger: "disk cleanup, free up space, temp files, clean cache, remove junk"
---

# Cleanup Tool

Safely clean temporary files, system caches, old Windows updates, browser caches, Recycle Bin, and find large files to purge.

## Usage

```
User: "Clean up my disk"
Agent: runs cleanup-tool (safe defaults)

User: "Free up space on C: drive"
Agent: runs cleanup-tool with target=C:

User: "What's taking up space?"
Agent: runs cleanup-tool action=analyze
```

## Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `action`  | `clean-safe`, `aggressive`, `analyze`, `large-files` | `clean-safe` |
| `target`  | Drive letter like `C:` or `D:` | `C:` |
| `minSizeMB` | Min file size for `large-files` (MB) | `500` |

## Safe Clean (recommended)

```powershell
# Windows Temp
Remove-Item "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "$env:WINDIR\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue

# User Temp
Remove-Item "$env:LOCALAPPDATA\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue

# Recycle Bin (empty)
Clear-RecycleBin -Force -ErrorAction SilentlyContinue

# Prefetch files (old ones only — keeps recent for boot speed)
Get-ChildItem "$env:WINDIR\Prefetch" -ErrorAction SilentlyContinue |
  Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) } |
  Remove-Item -Force -ErrorAction SilentlyContinue
```

## Cache Cleaners

```powershell
# Microsoft Store cache
wsreset.exe

# DNS cache
ipconfig /flushdns

# Windows Update cache
net stop wuauserv
Remove-Item "$env:WINDIR\SoftwareDistribution\Download\*" -Recurse -Force -ErrorAction SilentlyContinue
net start wuauserv

# Font cache
net stop "Windows Font Cache Service"
Remove-Item "$env:LOCALAPPDATA\Microsoft\Windows\FontCache\*" -Recurse -Force -ErrorAction SilentlyContinue
net start "Windows Font Cache Service"
```

## Analyze Disk Usage

```powershell
# Top-level folder sizes
$target = "C:"
Get-ChildItem "$target\" -Directory -ErrorAction SilentlyContinue |
  ForEach-Object {
    $size = (Get-ChildItem $_.FullName -Recurse -File -ErrorAction SilentlyContinue |
             Measure-Object -Property Length -Sum).Sum
    [PSCustomObject]@{
      Folder = $_.Name
      SizeGB = [math]::Round($size / 1GB, 2)
      SizeMB = [math]::Round($size / 1MB, 1)
    }
  } | Sort-Object SizeGB -Descending | Select-Object -First 20 | Format-Table -AutoSize

# Windows feature sizes
dism /Online /English /Get-FeatureInfo /FeatureName:* | Select-String "Feature Name|State"
```

## Find Large Files

```powershell
# Find files > minSizeMB on target drive
$minSizeMB = 500
$target = "C:"
Get-ChildItem "$target\" -Recurse -File -ErrorAction SilentlyContinue |
  Where-Object { $_.Length -gt ($minSizeMB * 1MB) } |
  Sort-Object Length -Descending |
  Select-Object -First 30 @{N="SizeGB";E={[math]::Round($_.Length/1GB,2)}},
    @{N="Path";E={$_.FullName}} |
  Format-Table -AutoSize
```

## Aggressive Clean (requires Admin)

```powershell
# DISM cleanup — removes superseded service pack files
dism /Online /Cleanup-Image /StartComponentCleanup /ResetBase

# WinSxS size check
dism /Online /Cleanup-Image /AnalyzeComponentStore

# Driver package cleanup
pnputil.exe /enum-drivers | Select-String "Published Name"
# Then remove old drivers with: pnputil.exe /delete-driver <inf>

# Windows.old (after Windows update — removes rollback ability)
# Check if exists: Get-ChildItem "$env:SystemDrive\Windows.old" -ErrorAction SilentlyContinue
# Remove: dism /Online /Remove-Image /ImageName:"Windows 11" (use cautiously)

# .NET Framework cleanup
# ngen.exe executequeueditems (if available)
```

## Browser Cache Cleanup

```powershell
# Edge
Remove-Item "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache\*" -Recurse -Force -ErrorAction SilentlyContinue

# Chrome
Remove-Item "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache\*" -Recurse -Force -ErrorAction SilentlyContinue

# Firefox
Remove-Item "$env:APPDATA\Mozilla\Firefox\Profiles\*\cache2\*" -Recurse -Force -ErrorAction SilentlyContinue
```

## Safety Notes

- `clean-safe` is non-destructive — only removes cache/temp files
- `aggressive` runs DISM /ResetBase — note: **prevents uninstalling recent updates**
- `analyze` is read-only — just reports what's taking space
- Large file detection may be slow on drives with many files

## Examples

```
User: "Free up disk space"
User: "Clean temp files"
User: "Show me what's filling C: drive"
User: "Run a quick system cleanup"
User: "Find files larger than 1GB"
User: "Clear Windows update cache"
```

## Related

- `disk-guardian` — proactive disk health monitoring
- `system-health` — full system diagnostic

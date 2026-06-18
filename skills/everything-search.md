---
name: everything-search
description: "Instant Windows file search via Everything SDK — replaces Windows Search with sub-second results"
trigger: "search files, find file, locate document, search for, where is, everything search"
---

# Everything Search

**Windows Search replacement** — sub-second file search across your entire system using voidtools Everything CLI (`es.exe`).

## Prerequisites

Install Everything from https://www.voidtools.com (free, 2MB). Enable the `es.exe` command-line interface:

```
# In Everything → Tools → Options → Indexes → CLI:
# Check "Enable ES HTTP Server" and note the port (default 8384)
# Or use the standalone es.exe from Everything installation folder
```

The skill auto-detects Everything if installed at default locations.

## Usage

```
User: "Find my tax documents from last month"
Agent: runs everything-search with query=tax, filter=*.pdf, date=last-month

User: "Where is my node_modules folder?"
Agent: runs everything-search with query=node_modules, folders-only

User: "Show me everything about 'budget' on my D drive"
Agent: runs everything-search with query=D:\budget

User: "Find large video files"
Agent: runs everything-search with query=*.mp4, min-size=1GB
```

## Parameters

| Parameter   | Description | Default |
|-------------|-------------|---------|
| `query`     | Search pattern (supports wildcards `*`, `?`) | (required) |
| `filter`    | File type filter: `*.pdf`, `*.docx`, `*.jpg`, or preset: `documents`, `images`, `video`, `music`, `code` | (all) |
| `path`      | Limit search to a folder like `C:\Users\*` or `D:\*` | (all drives) |
| `max`       | Max results to show | `20` |
| `min-size`  | Minimum file size (e.g. `100MB`, `1GB`) | (any) |
| `max-size`  | Maximum file size | (any) |
| `date-from` | Modified after this date (ISO: `2026-01-01`) | (any) |
| `date-to`   | Modified before this date | (any) |
| `folders-only` | Only show folders | `false` |
| `files-only`  | Only show files | `false` |

## Preset Filters

| Filter      | Includes |
|-------------|----------|
| `documents` | `*.pdf, *.docx, *.xlsx, *.pptx, *.txt, *.rtf, *.csv` |
| `images`    | `*.jpg, *.jpeg, *.png, *.gif, *.bmp, *.webp, *.svg` |
| `video`     | `*.mp4, *.mkv, *.avi, *.mov, *.wmv, *.flv` |
| `music`     | `*.mp3, *.flac, *.wav, *.aac, *.ogg, *.wma` |
| `code`      | `*.py, *.js, *.ts, *.java, *.cpp, *.cs, *.go, *.rs, *.rb, *.php, *.html, *.css` |

## PowerShell Commands

### Basic search

```powershell
# Find all PDFs (uses es.exe if available)
$query = "*.pdf"
if (Get-Command "es.exe" -ErrorAction SilentlyContinue) {
    es.exe $query -max-results 20
} else {
    # Fallback: native Windows search
    Get-ChildItem -Path C:\ -Filter $query -Recurse -ErrorAction SilentlyContinue |
        Select-Object -First 20 FullName, Length, LastWriteTime |
        Format-Table -AutoSize
}
```

### Advanced search with ES

```powershell
$query = "report"
$filter = "*.pdf"
$maxResults = 15
$path = "D:\"

es.exe "$query" -include-path "$path" -match-path `
    -sort Modified-Descending -max-results $maxResults `
    -format "{path}|{size}|{modified}" | ForEach-Object {
        $parts = $_ -split '\|'
        [PSCustomObject]@{
            Path = $parts[0]
            SizeMB = if ($parts[1] -as [long]) { [math]::Round([long]$parts[1]/1MB, 1) } else { 0 }
            Modified = $parts[2]
        }
    } | Format-Table -AutoSize
```

### Using Everything HTTP API

```powershell
$query = [System.Web.HttpUtility]::UrlEncode("report")
$esPort = 8384  # Default Everything HTTP server port
$results = Invoke-RestMethod "http://localhost:$esPort/search?q=$query&count=20" -ErrorAction SilentlyContinue
if ($results) {
    $results.items | Format-Table path, size, date_modified -AutoSize
}
```

### Size-aware search

```powershell
# Files larger than 500MB
$minSize = 500MB
$minSizeKB = $minSize / 1KB

es.exe "" -size-gte $minSizeKB -sort Size-Descending -max-results 20 `
    -format "{path}|{size:bytes}|{modified}" | ForEach-Object {
        $parts = $_ -split '\|'
        $sizeGB = [math]::Round([long]$parts[1]/1GB, 2)
        [PSCustomObject]@{ Path = $parts[0]; SizeGB = $sizeGB; Modified = $parts[2] }
    } | Format-Table -AutoSize
```

### Date-range search

```powershell
$dateFrom = "2026-01-01"
$dateTo = "2026-06-30"

es.exe "*.docx" -dm "$(Get-Date $dateFrom).$(Get-Date $dateTo)" `
    -sort Modified-Descending -max-results 15 `
    -format "{path}|{modified}"
```

## No Everything? Fallback

If Everything isn't installed, the skill falls back to native PowerShell `Get-ChildItem` (slower but works):

```powershell
# Slower native fallback — limits to avoid timeout
$results = Get-ChildItem -Path "C:\" -Filter "*.pdf" -Recurse -ErrorAction SilentlyContinue |
    Sort-Object Length -Descending |
    Select-Object -First 10
```

## Examples

```
User: "Find all Python files with 'import torch'"
User: "Where did I save that spreadsheet from yesterday?"
User: "Show me my top 10 largest files"
User: "Find all songs in my Music folder"
User: "Search for 'budget' in my Documents folder"
User: "Find images modified this week"
User: "Locate all node_modules folders on C: drive"
```

## Related

- `cleanup-tool` — clean up files found by large file search
- `disk-guardian` — monitor disk space
- `system-health` — full system diagnostic

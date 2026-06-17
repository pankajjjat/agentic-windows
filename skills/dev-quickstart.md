---
name: dev-quickstart
description: Scaffold development projects and install common developer tooling
version: 1.0
author: Agentic Windows
---

# Dev Quickstart

## Description
Quickly scaffold new development projects (React, Next.js, Python, Node.js), check development tools status, and install common developer tooling via winget.

## Triggers
- "Create a new project"
- "Scaffold a [type] project"
- "Run dev-quickstart"
- "Check dev tools"
- "Install development tools"
- "Setup dev environment"

## Steps

1. **Check Developer Tooling Status**
   ```powershell
   $tools = @(
     @{Name="Git"; Check="git --version"},
     @{Name="Node.js"; Check="node --version"},
     @{Name="npm"; Check="npm --version"},
     @{Name="Python"; Check="python --version"},
     @{Name="VS Code"; Check="code --version"},
     @{Name="Windows Terminal"; Check="wt --version"}
   )
   
   foreach ($t in $tools) {
     $result = & cmd /c "$($t.Check)" 2>$null
     if ($LASTEXITCODE -eq 0) { "✅ $($t.Name): $($result.Trim())" }
     else { "❌ $($t.Name): Not installed" }
   }
   ```

2. **Create Next.js Project** (if user specifies)
   ```powershell
   param($ProjectName)
   if ($ProjectName) {
     npx create-next-app@latest $ProjectName --typescript --tailwind --eslint --app --src-dir --import-alias "@/*"
     if ($LASTEXITCODE -eq 0) {
       "✅ Next.js project '$ProjectName' created"
       "cd $ProjectName && npm run dev"
     }
   }
   ```

3. **Create Python Project** (if user specifies)
   ```powershell
   param($ProjectName)
   if ($ProjectName) {
     mkdir $ProjectName -Force
     cd $ProjectName
     python -m venv venv
     "✅ Python project '$ProjectName' created with virtual environment"
   }
   ```

4. **Install Dev Tools via Winget**
   ```powershell
   param($ToolName)
   $wingetMap = @{
     "python" = "Python.Python.3.12"
     "node" = "OpenJS.NodeJS.LTS"
     "git" = "Git.Git"
     "vscode" = "Microsoft.VisualStudioCode"
     "terminal" = "Microsoft.WindowsTerminal"
     "docker" = "Docker.DockerDesktop"
     "powertoys" = "Microsoft.PowerToys"
     "everything" = "voidtools.Everything"
   }
   
   if ($ToolName -and $wingetMap[$ToolName]) {
     $pkg = $wingetMap[$ToolName]
     "📦 Installing $pkg via winget..."
     winget install --id $pkg --silent --accept-package-agreements
     if ($LASTEXITCODE -eq 0) { "✅ $ToolName installed" }
   }
   ```

## Example Commands
- "Create a Next.js project called my-blog" → scaffolds TypeScript + Tailwind + App Router
- "Create a Python project called data-analysis" → creates folder + venv
- "Install Docker" → winget install Docker
- "Check dev tools" → shows all tool versions
- "Set up my dev environment" → installs all core tools

## Output Format

```
╔══════════════════════════════════════════╗
║          DEV QUICKSTART                  ║
╚══════════════════════════════════════════╝

🛠️ DEV TOOLING STATUS:
  [tool status]

🚀 PROJECT CREATION:
  [project scaffold results]

📦 INSTALLATIONS:
  [install results]

💡 NEXT STEPS:
  • [project: cd into it and run dev server]
  • [tool: restart terminal to use it]
```

## Notes
- Project scaffolding creates in the current directory
- Dev tools install via winget (built-in on Windows 11)
- VS Code install via winget is the system variant (not user-specific)
- For team setups, consider version managers like nvm-windows or pyenv-win

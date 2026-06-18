<#
.SYNOPSIS
    AI Provider Setup Wizard — interactive one-click configuration for Hermes Agent
.DESCRIPTION
    Guides you through choosing an AI provider and entering your API key.
    Supports: OpenAI, Anthropic, OpenRouter, Google Gemini, Groq, Nous (managed).
    Writes config to ~/.hermes/config.yaml and tests the connection.
.NOTES
    Run as the logged-in user (not SYSTEM).
#>

param(
    [string]$Provider,  # Skip menu, configure this provider directly
    [switch]$List       # Just list available providers
)

$ErrorActionPreference = "Stop"
$CONFIG_DIR = "$env:LOCALAPPDATA\hermes"
$CONFIG_FILE = "$CONFIG_DIR\config.yaml"

function Write-Step  { Write-Host "  ⚡ $($args[0])" -ForegroundColor Cyan }
function Write-Info  { Write-Host "  ℹ️  $($args[0])" -ForegroundColor Cyan }
function Write-Good  { Write-Host "  ✅ $($args[0])" -ForegroundColor Green }
function Write-Warn  { Write-Host "  ⚠️  $($args[0])" -ForegroundColor Yellow }
function Write-Done  { Write-Host "$($args[0])" -ForegroundColor Green }

# Available providers
$providers = @(
    @{ Name="Nous (Managed)";     Key="nousresearch";   KeyLabel="API Key (from Nous dashboard)";   Template="nousresearch/llama-3.3-70b";  Managed=$true },
    @{ Name="OpenAI";             Key="openai";         KeyLabel="OpenAI API Key (sk-...)";          Template="gpt-4o";                       Managed=$false },
    @{ Name="Anthropic";          Key="anthropic";      KeyLabel="Anthropic API Key (sk-ant-...)";   Template="claude-sonnet-4-20250514";     Managed=$false },
    @{ Name="OpenRouter";         Key="openrouter";     KeyLabel="OpenRouter API Key";               Template="openrouter/anthropic/claude-3.5-sonnet"; Managed=$false },
    @{ Name="Google Gemini";      Key="google";         KeyLabel="Gemini API Key";                   Template="gemini/gemini-2.0-flash";      Managed=$false },
    @{ Name="Groq";               Key="groq";           KeyLabel="Groq API Key";                     Template="groq/llama3-70b-8192";         Managed=$false },
    @{ Name="DeepSeek";           Key="deepseek";       KeyLabel="DeepSeek API Key";                 Template="deepseek-chat";                 Managed=$false },
    @{ Name="Together AI";        Key="together";       KeyLabel="Together AI API Key";              Template="together_ai/meta-llama/Llama-3.3-70B-Instruct-Turbo"; Managed=$false }
)

if ($List) {
    Write-Step "Available providers:"
    foreach ($p in $providers) {
        $managed = if ($p.Managed) { "(managed — no key needed)" } else { "" }
        Write-Host "  $($p.Name) $managed"
    }
    exit 0
}

# ── Banner ──
Write-Host ""
Write-Host "  ┌─────────────────────────────────────┐" -ForegroundColor Cyan
Write-Host "  │   AI Provider Setup Wizard            │" -ForegroundColor Cyan
Write-Host "  │   Configure Hermes Agent in 2 minutes │" -ForegroundColor Cyan
Write-Host "  └─────────────────────────────────────┘" -ForegroundColor Cyan
Write-Host ""

# ── Existing config check ──
if (Test-Path $CONFIG_FILE) {
    $existing = Get-Content $CONFIG_FILE -Raw
    $hasProvider = $existing -match "provider:" -or $existing -match "api_key"
    if ($hasProvider) {
        Write-Warn "Existing Hermes config found at: $CONFIG_FILE"
        Write-Warn "This wizard will OVERWRITE your current provider settings."
        $continue = Read-Host "  Continue? (y/N) "
        if ($continue -ne "y") { Write-Info "Aborted."; exit 0 }
    }
}

# ── Provider selection ──
if (-not $Provider) {
    Write-Step "Choose your AI provider:"
    Write-Info "  (Managed = no API key needed if you have a Nous subscription)"
    Write-Info ""
    for ($i = 0; $i -lt $providers.Count; $i++) {
        $p = $providers[$i]
        $managed = if ($p.Managed) { " (managed)" } else { "" }
        Write-Host "  [$($i+1)] $($p.Name)$managed" -ForegroundColor White
    }
    Write-Host "  [$($providers.Count+1)] Custom (manual entry)" -ForegroundColor White
    Write-Info ""
    $choice = Read-Host "  Enter number (1-$($providers.Count+1))"
    $idx = [int]::TryParse($choice, [ref]$null) ? ([int]$choice - 1) : -1

    if ($idx -ge 0 -and $idx -lt $providers.Count) {
        $selected = $providers[$idx]
    } elseif ($idx -eq $providers.Count) {
        $selected = @{ Name="Custom"; Key="custom"; KeyLabel="Provider name + API key"; Template=""; Managed=$false }
        # Custom: ask for provider key name and model
        Write-Step "Custom provider setup"
        $customName = Read-Host "  Enter provider name (e.g. perplexity, cohere)"
        $selected.Key = "custom:$customName"
        $selected.KeyLabel = "$customName API Key"
        $customModel = Read-Host "  Enter default model name (e.g., $customName/model-name)"
        $selected.Template = $customModel
    } else {
        Write-Warn "Invalid choice. Aborting."
        exit 1
    }
} else {
    # Filter by provider key
    $selected = $providers | Where-Object { $_.Key -eq $Provider } | Select-Object -First 1
    if (-not $selected) {
        Write-Warn "Unknown provider: $Provider"
        exit 1
    }
}

$selectedName = $selected.Name
$selectedKey = $selected.Key
$selectedTemplate = $selected.Template
$isManaged = $selected.Managed

Write-Info "Selected: $selectedName"
Write-Info ""

# ── API Key ──
if ($isManaged) {
    Write-Good "Managed provider — no API key needed (uses Nous subscription)"
    $apiKey = ""
} else {
    Write-Step "Enter your API key:"
    Write-Info "  $($selected.KeyLabel)"
    Write-Info "  (Your key is stored locally — never sent anywhere but your provider)"
    $apiKey = Read-Host "  API key"
    if (-not $apiKey) {
        Write-Warn "No API key entered. Aborting."
        exit 1
    }
}

# ── Build config ──
Write-Step "Writing Hermes configuration..."
if (-not (Test-Path $CONFIG_DIR)) {
    New-Item -ItemType Directory -Path $CONFIG_DIR -Force | Out-Null
}

$newConfig = @"
# ── Auto-generated by setup-provider.ps1 ──
provider: $selectedKey
model: $selectedTemplate

system_prompt: |
  You are Hermes, an AI assistant deeply integrated into Windows 11.
  You have access to the system's processes, files, services, and hardware.
  Help the user manage their computer efficiently.

# Local LLM fallback (optional)
# provider: custom:local
# model: llama.cpp

cache_enabled: true
max_tokens: 8192
temperature: 0.7
"@

if ($apiKey) {
    $newConfig += "`napi_key: $apiKey"
}

# Read existing config and preserve non-provider settings
if (Test-Path $CONFIG_FILE) {
    $existing = Get-Content $CONFIG_FILE -Raw
    # Keep anything not provider/model/api_key related
    $preserved = @()
    $inProviderBlock = $false
    foreach ($line in $existing -split "`n") {
        if ($line -match "^(provider|model|api_key|system_prompt)") { $inProviderBlock = $true; continue }
        if ($inProviderBlock -and $line -match "^[a-z]") { $inProviderBlock = $false }
        if (-not $inProviderBlock -and $line -notmatch "^system_prompt" -and $line -notmatch "^\s*$") {
            $preserved += $line
        }
    }
    if ($preserved.Count -gt 0) {
        $newConfig += "`n`n# Preserved settings`n" + ($preserved -join "`n")
    }
}

$newConfig | Set-Content -Path $CONFIG_FILE -Encoding UTF8
Write-Good "Config written to: $CONFIG_FILE"

# ── Test connection ──
Write-Step "Testing connection..."
$testResult = & hermes --no-tools "Hello, are you working?" 2>&1
if ($LASTEXITCODE -eq 0 -and $testResult) {
    Write-Good "Connection successful! Hermes is ready."
    Write-Info "Response: $($testResult.Trim().Substring(0, [Math]::Min(100, $testResult.Trim().Length)))..."
} else {
    Write-Warn "Connection test returned: $testResult"
    Write-Info "Your config is saved but the test didn't pass. Check your API key in $CONFIG_FILE"
}

# ── Summary ──
Write-Host ""
Write-Host "  ┌─────────────────────────────────────────┐" -ForegroundColor Green
Write-Host "  │   ✅  Provider configured!               │" -ForegroundColor Green
Write-Host "  └─────────────────────────────────────────┘" -ForegroundColor Green
Write-Host ""
Write-Info "  Provider: $selectedName"
Write-Info "  Model:    $selectedTemplate"
Write-Info "  Config:   $CONFIG_FILE"
Write-Host ""
Write-Info "  Try: hermes 'What is my system status?'"
Write-Info "  Or:  hermes run skill system-health"
Write-Host ""

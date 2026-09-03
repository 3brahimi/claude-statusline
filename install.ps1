# Claude Code Statusline Installer — Windows
# Usage: irm https://path/to/install.ps1 | iex
#    or: powershell -ExecutionPolicy Bypass -File install.ps1

param(
    [switch]$Quiet   # Suppress output
)

$ErrorActionPreference = "Stop"

# ── Paths ─────────────────────────────────────────────────────────────────────
$claudeDir = Join-Path $env:USERPROFILE ".claude"
$settingsPath = Join-Path $claudeDir "settings.json"
$scriptPath = Join-Path $claudeDir "statusline-command.ps1"
$scriptURL = "https://raw.githubusercontent.com/3brahimi/claude-statusline/main/statusline-command.ps1"

function Write-Info([string]$msg) {
    if (-not $Quiet) { Write-Host "✓ $msg" -ForegroundColor Green }
}

function Write-Error-Custom([string]$msg) {
    Write-Host "✗ $msg" -ForegroundColor Red
    exit 1
}

try {
    # ── Create ~/.claude if needed ────────────────────────────────────────────
    if (-not (Test-Path $claudeDir)) {
        New-Item -ItemType Directory -Path $claudeDir -Force | Out-Null
        Write-Info "Created directory: $claudeDir"
    }

    # ── Download/copy statusline script ───────────────────────────────────────
    # If running locally (has a script dir), copy from there; otherwise this is
    # a remote `irm | iex` run ($PSScriptRoot is empty) — download it instead.
    $localScript = if ($PSScriptRoot) { Join-Path $PSScriptRoot "statusline-command.ps1" } else { $null }

    if ($localScript -and (Test-Path $localScript)) {
        Copy-Item $localScript $scriptPath -Force
        Write-Info "Copied statusline script to: $scriptPath"
    } else {
        Invoke-WebRequest -Uri $scriptURL -OutFile $scriptPath -UseBasicParsing
        Write-Info "Downloaded statusline script to: $scriptPath"
    }

    # ── Update settings.json ──────────────────────────────────────────────────
    if (Test-Path $settingsPath) {
        $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json
    } else {
        $settings = @{}
    }

    # Ensure statusLine object exists
    if (-not $settings.statusLine) {
        $settings | Add-Member -NotePropertyName "statusLine" -NotePropertyValue @{}
    }

    # Update with command and type
    $settings.statusLine = @{
        "type"    = "command"
        "command" = "pwsh -ExecutionPolicy Bypass -File `"$scriptPath`""
    }

    # Write back to file (preserve formatting as much as possible)
    $settings | ConvertTo-Json -Depth 10 | Set-Content $settingsPath -Encoding UTF8
    Write-Info "Updated: $settingsPath"

    # ── Verify ────────────────────────────────────────────────────────────────
    if (Test-Path $scriptPath) {
        Write-Info "Statusline installation complete!"
        Write-Info "Restart Claude Code to apply changes"
    } else {
        Write-Error-Custom "Installation failed: script not found at $scriptPath"
    }

} catch {
    Write-Error-Custom "Installation failed: $_"
}

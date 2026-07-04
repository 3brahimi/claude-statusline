#!/usr/bin/env bash
# Claude Code Statusline Installer — Linux/macOS
# Usage: curl -sSL https://path/to/install.sh | bash
#    or: bash install.sh

set -e

CLAUDE_DIR="$HOME/.claude"
SETTINGS_PATH="$CLAUDE_DIR/settings.json"
SCRIPT_PATH="$CLAUDE_DIR/statusline-command.sh"
SCRIPT_URL="https://raw.githubusercontent.com/YOUR_REPO_HERE/statusline-command.sh"

# Detect if running from script dir or need to download
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_SCRIPT="$SCRIPT_DIR/statusline-command.sh"

info() { echo "✓ $1"; }
error() { echo "✗ $1" >&2; exit 1; }

# ── Create ~/.claude if needed ────────────────────────────────────────────────
if [[ ! -d "$CLAUDE_DIR" ]]; then
    mkdir -p "$CLAUDE_DIR"
    info "Created directory: $CLAUDE_DIR"
fi

# ── Copy/download statusline script ───────────────────────────────────────────
if [[ -f "$LOCAL_SCRIPT" ]]; then
    cp "$LOCAL_SCRIPT" "$SCRIPT_PATH"
    info "Copied statusline script to: $SCRIPT_PATH"
else
    error "statusline-command.sh not found in $SCRIPT_DIR"
fi

# Make it executable
chmod +x "$SCRIPT_PATH"
info "Made script executable"

# ── Update settings.json ──────────────────────────────────────────────────────
# If settings.json doesn't exist, create a minimal one
if [[ ! -f "$SETTINGS_PATH" ]]; then
    cat > "$SETTINGS_PATH" <<EOF
{
  "statusLine": {
    "type": "command",
    "command": "bash $SCRIPT_PATH"
  }
}
EOF
    info "Created: $SETTINGS_PATH"
else
    # Update existing settings.json with jq if available, else sed
    if command -v jq &>/dev/null; then
        jq ".statusLine = {\"type\": \"command\", \"command\": \"bash $SCRIPT_PATH\"}" \
            "$SETTINGS_PATH" > "$SETTINGS_PATH.tmp"
        mv "$SETTINGS_PATH.tmp" "$SETTINGS_PATH"
        info "Updated: $SETTINGS_PATH (using jq)"
    else
        # Fallback: basic sed (less reliable, but works)
        # This is a simplified approach — full JSON editing without jq is fragile
        echo "Warning: jq not found, attempting manual JSON update (may be incomplete)"
        info "Please manually update $SETTINGS_PATH with:"
        echo "  \"statusLine\": {"
        echo "    \"type\": \"command\","
        echo "    \"command\": \"bash $SCRIPT_PATH\""
        echo "  }"
    fi
fi

# ── Verify ────────────────────────────────────────────────────────────────────
if [[ -f "$SCRIPT_PATH" ]]; then
    info "Statusline installation complete!"
    info "Restart Claude Code to apply changes"
else
    error "Installation failed: script not found at $SCRIPT_PATH"
fi

#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_SRC="$SCRIPT_DIR/skills/cmail"
SKILL_DST="$HOME/.claude/skills/cmail"
HOOKS_SRC="$SKILL_SRC/scripts/hooks"
CLAUDE_SETTINGS="$HOME/.claude/settings.json"

echo "=== cmail Installer ==="
echo ""

# --- Step 1: Symlink skill into ~/.claude/skills/ ---

mkdir -p "$HOME/.claude/skills"

if [[ -L "$SKILL_DST" ]]; then
  echo "Removing existing symlink: $SKILL_DST"
  rm "$SKILL_DST"
elif [[ -d "$SKILL_DST" ]]; then
  echo "Warning: $SKILL_DST exists and is not a symlink."
  read -r -p "Replace it? [y/N] " confirm
  if [[ "$confirm" =~ ^[Yy]$ ]]; then
    rm -rf "$SKILL_DST"
  else
    echo "Aborted."
    exit 1
  fi
fi

ln -s "$SKILL_SRC" "$SKILL_DST"
echo "Linked: $SKILL_DST -> $SKILL_SRC"

# Make scripts executable
chmod +x "$SKILL_SRC/scripts/cmail.sh"
chmod +x "$HOOKS_SRC"/*.sh 2>/dev/null || true
echo "Made scripts executable."

# --- Step 2: Install cmail to PATH ---

BIN_DIR="/usr/local/bin"
LINK_OK=false
if [[ -w "$BIN_DIR" ]]; then
  rm -f "$BIN_DIR/cmail"
  ln -s "$SKILL_SRC/scripts/cmail.sh" "$BIN_DIR/cmail" && LINK_OK=true
elif command -v sudo &>/dev/null; then
  sudo rm -f "$BIN_DIR/cmail" 2>/dev/null && \
  sudo ln -s "$SKILL_SRC/scripts/cmail.sh" "$BIN_DIR/cmail" 2>/dev/null && LINK_OK=true
fi

if [[ "$LINK_OK" == true ]]; then
  echo "Linked: $BIN_DIR/cmail -> cmail.sh (available globally)"
else
  echo "Note: Could not install to $BIN_DIR. Trying ~/.local/bin instead."
  mkdir -p "$HOME/.local/bin"
  rm -f "$HOME/.local/bin/cmail"
  ln -s "$SKILL_SRC/scripts/cmail.sh" "$HOME/.local/bin/cmail"
  echo "Linked: ~/.local/bin/cmail -> cmail.sh"
  if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
    echo "  Add to PATH: export PATH=\"\$HOME/.local/bin:\$PATH\""
  fi
fi

# --- Step 3: Initialize ~/.cmail/ structure ---

mkdir -p "$HOME/.cmail/inbox" "$HOME/.cmail/outbox"
echo "Created ~/.cmail/ directories."

if [[ ! -f "$HOME/.cmail/config.json" ]]; then
  IDENTITY="$(hostname | tr '[:upper:]' '[:lower:]' | sed 's/\.local$//')"
  cat > "$HOME/.cmail/config.json" <<EOF
{
  "identity": "$IDENTITY",
  "hosts": {}
}
EOF
  echo "Created default config with identity: $IDENTITY"
else
  echo "Config already exists, skipping."
fi

# --- Step 4: Auto-start watcher in shell profile ---

WATCH_LINE='command -v cmail &>/dev/null && cmail watch --daemon &>/dev/null &'
SHELL_RC=""
if [[ -f "$HOME/.zshrc" ]]; then
  SHELL_RC="$HOME/.zshrc"
elif [[ -f "$HOME/.bashrc" ]]; then
  SHELL_RC="$HOME/.bashrc"
elif [[ -f "$HOME/.bash_profile" ]]; then
  SHELL_RC="$HOME/.bash_profile"
fi

if [[ -n "$SHELL_RC" ]]; then
  if ! grep -qF "cmail watch --daemon" "$SHELL_RC" 2>/dev/null; then
    echo "" >> "$SHELL_RC"
    echo "# cmail: auto-start inbox watcher" >> "$SHELL_RC"
    echo "$WATCH_LINE" >> "$SHELL_RC"
    echo "Added cmail watcher to $SHELL_RC"
  else
    echo "Watcher already in $SHELL_RC, skipping."
  fi
else
  echo "Note: Could not find shell rc file. Add this to your shell profile manually:"
  echo "  $WATCH_LINE"
fi

# --- Step 5: Register Claude Code permissions and hooks ---

install_permissions_and_hooks() {
  if [[ ! -f "$CLAUDE_SETTINGS" ]]; then
    echo "No Claude Code settings found at $CLAUDE_SETTINGS — skipping."
    return 0
  fi

  if ! command -v jq &>/dev/null; then
    echo "jq not found — skipping settings registration. Install jq and re-run."
    return 0
  fi

  local tmp="$CLAUDE_SETTINGS.tmp"
  local changed=false

  # --- Permissions ---
  local cmail_perms=(
    'Bash(cmail *)'
    'Bash(~/.claude/skills/cmail/scripts/cmail.sh *)'
    'Bash(rm -f ~/.cmail/inbox/*.json *)'
    'Bash(rm -f ~/.cmail/.has_unread)'
    'Bash(rm -f ~/.cmail/.last_stop_check)'
    'Bash(ls ~/.cmail/inbox/*)'
    'Bash(tailscale ssh *)'
    'Bash(claude --print *)'
  )

  # Check which permissions are missing
  local existing_perms
  existing_perms="$(jq -r '.permissions.allow // [] | .[]' "$CLAUDE_SETTINGS" 2>/dev/null)" || true

  local perms_to_add=()
  for perm in "${cmail_perms[@]}"; do
    if ! echo "$existing_perms" | grep -qF "$perm"; then
      perms_to_add+=("$perm")
    fi
  done

  if [[ ${#perms_to_add[@]} -gt 0 ]]; then
    local perms_json
    perms_json="$(printf '%s\n' "${perms_to_add[@]}" | jq -R . | jq -s .)"
    jq --argjson new "$perms_json" '
      .permissions //= {} |
      .permissions.allow = ((.permissions.allow // []) + $new | unique)
    ' "$CLAUDE_SETTINGS" > "$tmp" && mv "$tmp" "$CLAUDE_SETTINGS"
    echo "Added ${#perms_to_add[@]} cmail permissions."
    changed=true
  else
    echo "cmail permissions already registered."
  fi

  # --- Hooks ---
  local session_start="$HOOKS_SRC/session-start.sh"
  local user_prompt="$HOOKS_SRC/user-prompt-submit.sh"
  local stop_hook="$HOOKS_SRC/stop.sh"

  if jq -r '.hooks | .. | .command? // empty' "$CLAUDE_SETTINGS" 2>/dev/null | grep -q "cmail"; then
    echo "cmail hooks already registered."
  else
    jq --arg ss "$session_start" --arg up "$user_prompt" --arg st "$stop_hook" '
      .hooks //= {} |
      .hooks.SessionStart = (.hooks.SessionStart // []) + [{
        "hooks": [{"type": "command", "command": $ss, "timeout": 10}]
      }] |
      .hooks.UserPromptSubmit = (.hooks.UserPromptSubmit // []) + [{
        "hooks": [{"type": "command", "command": $up, "timeout": 5}]
      }] |
      .hooks.Stop = (.hooks.Stop // []) + [{
        "hooks": [{"type": "command", "command": $st, "timeout": 10}]
      }]
    ' "$CLAUDE_SETTINGS" > "$tmp" && mv "$tmp" "$CLAUDE_SETTINGS"
    echo "Registered Claude Code hooks (SessionStart, UserPromptSubmit, Stop)."
    changed=true
  fi

  if [[ "$changed" == true ]]; then
    echo "  Updated: $CLAUDE_SETTINGS"
  fi
}

install_permissions_and_hooks

# --- Step 6: Status line integration ---

STATUSLINE_SCRIPT="$HOME/.claude/statusline-command.sh"
CMAIL_MARKER="# cmail-statusline-start"

if [[ -f "$STATUSLINE_SCRIPT" ]]; then
  if grep -qF "$CMAIL_MARKER" "$STATUSLINE_SCRIPT" 2>/dev/null || grep -qF 'cmail_info' "$STATUSLINE_SCRIPT" 2>/dev/null; then
    echo "cmail statusline already present, skipping."
  else
    cat >> "$STATUSLINE_SCRIPT" <<'CMAIL_EOF'

# cmail-statusline-start
# cmail inbox count (added by cmail installer)
_cmail_count=$(ls -1 "$HOME/.cmail/inbox/"*.json 2>/dev/null | wc -l | tr -d ' ')
if (( _cmail_count > 0 )); then
    _cmail_info=" \033[38;2;128;128;128m|\033[0m \033[1m(${_cmail_count})\033[22m cmail"
else
    _cmail_info=" \033[38;2;128;128;128m|\033[0m \033[38;2;128;128;128m(0) cmail\033[0m"
fi
# cmail-statusline-end
CMAIL_EOF
    echo "Added cmail count to statusline script."
    echo "  Note: Add \${_cmail_info} to your status line output variable to display it."
  fi
else
  echo "No statusline script found — status line integration skipped."
  echo "  To add manually, see: cmail setup"
fi

# --- Step 7: Start watcher ---

"$SKILL_SRC/scripts/cmail.sh" watch --daemon &>/dev/null &
echo "Started cmail watcher (PID: $!)."

# --- Done ---

echo ""
echo "Installation complete!"
echo ""
echo "Next steps:"
echo "  1. Run guided setup:  cmail setup"
echo "  2. Test connectivity:  cmail hosts"
echo "  3. Send a message:     cmail send <host> \"hello\""

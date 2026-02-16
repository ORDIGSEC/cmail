#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_SRC="$SCRIPT_DIR/skills/cmail"
SKILL_DST="$HOME/.claude/skills/cmail"

echo "=== cmail Installer ==="
echo ""

# Symlink skill into ~/.claude/skills/
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

# Make script executable
chmod +x "$SKILL_SRC/scripts/cmail.sh"
echo "Made cmail.sh executable."

# Install cmail to PATH so it's available globally (even in sandboxed Claude sessions)
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

# Initialize ~/.cmail/ structure
mkdir -p "$HOME/.cmail/inbox" "$HOME/.cmail/outbox"
echo "Created ~/.cmail/ directories."

# Create default config if it doesn't exist
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

echo ""
echo "Installation complete!"
echo ""
echo "Next steps:"
echo "  1. Add hosts:  cmail setup"
echo "  2. Test:       cmail hosts"
echo "  3. Send:       cmail send <host> \"hello\""

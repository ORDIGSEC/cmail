#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_SRC="$SCRIPT_DIR/skills/claudecomms"
SKILL_DST="$HOME/.claude/skills/claudecomms"

echo "=== claudeComms Installer ==="
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
chmod +x "$SKILL_SRC/scripts/claudecomms.sh"
echo "Made claudecomms.sh executable."

# Initialize ~/.claudecomms/ structure
mkdir -p "$HOME/.claudecomms/inbox" "$HOME/.claudecomms/outbox"
echo "Created ~/.claudecomms/ directories."

# Create default config if it doesn't exist
if [[ ! -f "$HOME/.claudecomms/config.json" ]]; then
  IDENTITY="$(hostname | tr '[:upper:]' '[:lower:]' | sed 's/\.local$//')"
  cat > "$HOME/.claudecomms/config.json" <<EOF
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
echo "  1. Add hosts:  ~/.claude/skills/claudecomms/scripts/claudecomms.sh setup"
echo "  2. Test:       ~/.claude/skills/claudecomms/scripts/claudecomms.sh hosts"
echo "  3. Send:       ~/.claude/skills/claudecomms/scripts/claudecomms.sh send <host> \"hello\""

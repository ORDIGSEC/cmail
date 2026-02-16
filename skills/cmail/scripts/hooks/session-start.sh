#!/usr/bin/env bash
# cmail SessionStart hook — check inbox when a Claude session starts or resumes
set -euo pipefail

INBOX_DIR="$HOME/.cmail/inbox"
UNREAD_MARKER="$HOME/.cmail/.has_unread"

# Fast path: no marker means no new messages
if [[ ! -f "$UNREAD_MARKER" ]]; then
  exit 0
fi

# Count inbox messages
count=$(ls -1 "$INBOX_DIR"/*.json 2>/dev/null | wc -l | tr -d ' ')
if (( count == 0 )); then
  exit 0
fi

# Build a summary of the newest messages (up to 5)
summary=""
for file in $(ls -1t "$INBOX_DIR"/*.json 2>/dev/null | head -5); do
  if command -v jq &>/dev/null; then
    from=$(jq -r '.from // "unknown"' "$file")
    subject=$(jq -r '.subject // ""' "$file")
    timestamp=$(jq -r '.timestamp // ""' "$file")
  else
    from=$(python3 -c "import json; print(json.load(open('$file')).get('from','unknown'))" 2>/dev/null || echo "unknown")
    subject=$(python3 -c "import json; print(json.load(open('$file')).get('subject',''))" 2>/dev/null || echo "")
    timestamp=$(python3 -c "import json; print(json.load(open('$file')).get('timestamp',''))" 2>/dev/null || echo "")
  fi
  entry="- ${timestamp} from ${from}"
  [[ -n "$subject" && "$subject" != "null" ]] && entry+=" — ${subject}"
  summary+="${entry}\n"
done

context="You have ${count} cmail message(s) in your inbox. Run \`cmail inbox\` to see them or \`cmail read <id>\` to read one.\n\nNewest messages:\n${summary}"

# Output JSON with additionalContext for Claude
if command -v jq &>/dev/null; then
  jq -n --arg ctx "$context" '{"additionalContext": $ctx}'
else
  python3 -c "import json; print(json.dumps({'additionalContext': '''$context'''}))"
fi

exit 0

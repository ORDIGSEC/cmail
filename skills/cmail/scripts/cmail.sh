#!/usr/bin/env bash
set -euo pipefail

COMMS_DIR="$HOME/.cmail"
INBOX_DIR="$COMMS_DIR/inbox"
OUTBOX_DIR="$COMMS_DIR/outbox"
CONFIG_FILE="$COMMS_DIR/config.json"
UNREAD_MARKER="$COMMS_DIR/.has_unread"

DEPS_CHECKED_MARKER="$COMMS_DIR/.deps_checked"

# --- Dependency Management ---

detect_pkg_manager() {
  if command -v brew &>/dev/null; then echo "brew"
  elif command -v apt-get &>/dev/null; then echo "apt"
  elif command -v dnf &>/dev/null; then echo "dnf"
  elif command -v yum &>/dev/null; then echo "yum"
  elif command -v pacman &>/dev/null; then echo "pacman"
  elif command -v apk &>/dev/null; then echo "apk"
  else echo "unknown"
  fi
}

install_pkg() {
  local pkg="$1"
  local mgr
  mgr="$(detect_pkg_manager)"
  case "$mgr" in
    brew)   brew install "$pkg" ;;
    apt)    sudo apt-get install -y "$pkg" ;;
    dnf)    sudo dnf install -y "$pkg" ;;
    yum)    sudo yum install -y "$pkg" ;;
    pacman) sudo pacman -S --noconfirm "$pkg" ;;
    apk)    sudo apk add "$pkg" ;;
    *)      return 1 ;;
  esac
}

# Maps logical dep names to package names per manager
pkg_name() {
  local dep="$1" mgr="$2"
  case "$dep" in
    jq) echo "jq" ;;
    fswatch) echo "fswatch" ;;
    inotifywait)
      case "$mgr" in
        apt|dnf|yum) echo "inotify-tools" ;;
        pacman) echo "inotify-tools" ;;
        apk) echo "inotify-tools" ;;
        *) echo "inotify-tools" ;;
      esac
      ;;
  esac
}

check_deps() {
  # Skip if already checked this install
  [[ -f "$DEPS_CHECKED_MARKER" ]] && return 0

  mkdir -p "$COMMS_DIR"
  local missing=()

  # jq is strongly recommended
  if ! command -v jq &>/dev/null; then
    missing+=("jq")
  fi

  # File watcher (platform-dependent)
  if [[ "$(uname)" == "Darwin" ]]; then
    if ! command -v fswatch &>/dev/null; then
      missing+=("fswatch")
    fi
  else
    if ! command -v inotifywait &>/dev/null; then
      missing+=("inotifywait")
    fi
  fi

  if [[ ${#missing[@]} -eq 0 ]]; then
    touch "$DEPS_CHECKED_MARKER"
    return 0
  fi

  local mgr
  mgr="$(detect_pkg_manager)"

  echo "cmail: missing optional dependencies: ${missing[*]}"

  if [[ "$mgr" == "unknown" ]]; then
    echo "Could not detect package manager. Please install manually: ${missing[*]}"
    # Don't block — deps are optional
    touch "$DEPS_CHECKED_MARKER"
    return 0
  fi

  echo "Install them now? (Uses $mgr) [Y/n] "
  read -r confirm </dev/tty 2>/dev/null || confirm="y"
  if [[ "$confirm" =~ ^[Nn] ]]; then
    echo "Skipping. cmail will use fallbacks where available."
    touch "$DEPS_CHECKED_MARKER"
    return 0
  fi

  for dep in "${missing[@]}"; do
    local actual_pkg
    actual_pkg="$(pkg_name "$dep" "$mgr")"
    echo "Installing $actual_pkg..."
    if install_pkg "$actual_pkg"; then
      echo "  Installed $actual_pkg"
    else
      echo "  Failed to install $actual_pkg — continuing without it"
    fi
  done

  touch "$DEPS_CHECKED_MARKER"
}

cmd_deps() {
  # Force re-check by removing marker
  rm -f "$DEPS_CHECKED_MARKER"
  check_deps
  echo ""
  echo "Dependency status:"
  printf "  %-15s %s\n" "jq" "$(command -v jq &>/dev/null && echo "installed" || echo "missing (using python3 fallback)")"
  printf "  %-15s %s\n" "python3" "$(command -v python3 &>/dev/null && echo "installed" || echo "missing")"
  if [[ "$(uname)" == "Darwin" ]]; then
    printf "  %-15s %s\n" "fswatch" "$(command -v fswatch &>/dev/null && echo "installed" || echo "missing (needed for watch command)")"
  else
    printf "  %-15s %s\n" "inotifywait" "$(command -v inotifywait &>/dev/null && echo "installed" || echo "missing (needed for watch command)")"
  fi
  printf "  %-15s %s\n" "ssh" "$(command -v ssh &>/dev/null && echo "installed" || echo "missing")"
  printf "  %-15s %s\n" "tailscale" "$(command -v tailscale &>/dev/null && echo "installed" || echo "not found")"
}

# --- Helpers ---

ensure_dirs() {
  mkdir -p "$INBOX_DIR" "$OUTBOX_DIR"
}

ensure_config() {
  ensure_dirs
  if [[ ! -f "$CONFIG_FILE" ]]; then
    local identity
    identity="$(hostname | tr '[:upper:]' '[:lower:]' | sed 's/\.local$//')"
    cat > "$CONFIG_FILE" <<EOF
{
  "identity": "$identity",
  "hosts": {}
}
EOF
    echo "Created config with identity: $identity"
    echo "Run 'cmail setup' to add hosts."
  fi
}

get_identity() {
  ensure_config
  json_get "$CONFIG_FILE" '.identity'
}

generate_uuid() {
  if command -v uuidgen &>/dev/null; then
    uuidgen | tr '[:upper:]' '[:lower:]'
  elif [[ -f /proc/sys/kernel/random/uuid ]]; then
    cat /proc/sys/kernel/random/uuid
  else
    python3 -c "import uuid; print(uuid.uuid4())"
  fi
}

get_timestamp() {
  if date -u +%Y-%m-%dT%H:%M:%S.000Z 2>/dev/null; then
    return
  fi
  python3 -c "from datetime import datetime, timezone; print(datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%S.000Z'))"
}

get_filename_timestamp() {
  if date -u +%Y%m%dT%H%M%S.000Z 2>/dev/null; then
    return
  fi
  python3 -c "from datetime import datetime, timezone; print(datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S.000Z'))"
}

json_get() {
  local file="$1" query="$2"
  if command -v jq &>/dev/null; then
    jq -r "$query" "$file"
  else
    python3 -c "import json,sys; data=json.load(open('$file')); print(eval('data' + ''.join('[\"' + k + '\"]' if not k.startswith('[') else k for k in '$query'.replace('.','.|').split('|')[1:])))" 2>/dev/null || echo "null"
  fi
}

json_get_str() {
  local str="$1" query="$2"
  if command -v jq &>/dev/null; then
    echo "$str" | jq -r "$query"
  else
    python3 -c "import json,sys; data=json.loads(sys.stdin.read()); exec('result = data' + ''.join('[\"' + k + '\"]' if not k.startswith('[') else k for k in '$query'.replace('.','.|').split('|')[1:])); print(result)" <<< "$str" 2>/dev/null || echo "null"
  fi
}

get_host_address() {
  local host="$1"
  ensure_config
  if command -v jq &>/dev/null; then
    jq -r ".hosts[\"$host\"].address // empty" "$CONFIG_FILE"
  else
    python3 -c "
import json
with open('$CONFIG_FILE') as f:
    data = json.load(f)
addr = data.get('hosts', {}).get('$host', {}).get('address', '')
if addr: print(addr)
"
  fi
}

get_host_ssh_method() {
  local host="$1"
  ensure_config
  if command -v jq &>/dev/null; then
    jq -r ".hosts[\"$host\"].ssh_method // \"tailscale\"" "$CONFIG_FILE"
  else
    python3 -c "
import json
with open('$CONFIG_FILE') as f:
    data = json.load(f)
method = data.get('hosts', {}).get('$host', {}).get('ssh_method', 'tailscale')
print(method)
"
  fi
}

auto_update_ssh_method() {
  local addr="$1"
  # Update config so future calls skip the failed tailscale attempt
  # Looks up hosts by address since callers pass the address, not the name
  if command -v jq &>/dev/null; then
    jq --arg addr "$addr" \
      '(.hosts | to_entries[] | select(.value.address == $addr) | .key) as $name |
       if $name then .hosts[$name].ssh_method = "standard" else . end' \
      "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
  else
    python3 -c "
import json
with open('$CONFIG_FILE', 'r') as f: data = json.load(f)
for name, info in data.get('hosts', {}).items():
    if info.get('address') == '$addr':
        info['ssh_method'] = 'standard'
        break
with open('$CONFIG_FILE', 'w') as f: json.dump(data, f, indent=2)
" 2>/dev/null
  fi
}

ssh_exec() {
  local address="$1" method="$2"
  shift 2
  if [[ "$method" == "tailscale" ]]; then
    if tailscale ssh "$address" "$@" 2>/dev/null; then
      return 0
    fi
    auto_update_ssh_method "$address"
  fi
  ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new "$address" "$@"
}

ssh_pipe() {
  local address="$1" method="$2" remote_cmd="$3"
  if [[ "$method" == "tailscale" ]]; then
    if tailscale ssh "$address" "$remote_cmd" 2>/dev/null; then
      return 0
    fi
    auto_update_ssh_method "$address"
  fi
  ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new "$address" "$remote_cmd"
}

# --- Commands ---

cmd_setup() {
  ensure_config

  local CLAUDE_SETTINGS="$HOME/.claude/settings.json"
  local HOOKS_DIR
  HOOKS_DIR="$(cd "$(dirname "$0")" && pwd)/hooks"
  local STATUSLINE_SCRIPT="$HOME/.claude/statusline-command.sh"

  echo "╔══════════════════════════════════════╗"
  echo "║           cmail setup                ║"
  echo "╚══════════════════════════════════════╝"
  echo ""

  # --- 1. Identity ---
  echo "── Step 1/5: Identity ──"
  echo ""
  local identity
  identity="$(json_get "$CONFIG_FILE" '.identity')"
  echo "  Your identity is how other machines see you."
  echo "  Current: $identity"
  read -r -p "  New identity (Enter to keep): " new_identity </dev/tty 2>/dev/null || new_identity=""
  if [[ -n "$new_identity" ]]; then
    if command -v jq &>/dev/null; then
      jq --arg id "$new_identity" '.identity = $id' "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
    else
      python3 -c "
import json
with open('$CONFIG_FILE', 'r') as f: data = json.load(f)
data['identity'] = '$new_identity'
with open('$CONFIG_FILE', 'w') as f: json.dump(data, f, indent=2)
"
    fi
    identity="$new_identity"
    echo "  Set to: $identity"
  else
    echo "  Keeping: $identity"
  fi
  echo ""

  # --- 2. Hosts ---
  echo "── Step 2/5: Remote Hosts ──"
  echo ""

  # Show existing hosts
  local existing_hosts=""
  if command -v jq &>/dev/null; then
    existing_hosts="$(jq -r '.hosts | keys[]' "$CONFIG_FILE" 2>/dev/null)" || true
  else
    existing_hosts="$(python3 -c "
import json
with open('$CONFIG_FILE') as f: data = json.load(f)
for k in data.get('hosts', {}): print(k)
" 2>/dev/null)" || true
  fi

  if [[ -n "$existing_hosts" ]]; then
    echo "  Existing hosts:"
    while IFS= read -r h; do
      local addr
      addr="$(get_host_address "$h")"
      local method
      method="$(get_host_ssh_method "$h")"
      echo "    $h -> $addr ($method)"
    done <<< "$existing_hosts"
    echo ""
  fi

  echo "  Add remote machines you want to message."
  echo "  Leave name blank when done."
  echo ""
  while true; do
    read -r -p "  Host name: " host_name </dev/tty 2>/dev/null || host_name=""
    [[ -z "$host_name" ]] && break
    read -r -p "  Address (Tailscale hostname or IP): " host_addr </dev/tty 2>/dev/null || host_addr=""
    [[ -z "$host_addr" ]] && { echo "  Address required, skipping."; continue; }

    echo "  SSH method:"
    echo "    1) tailscale — uses 'tailscale ssh' (no keys needed)"
    echo "    2) standard  — uses regular 'ssh' (needs keys/password)"
    read -r -p "  Choose [1/2] (default: 1): " method_choice </dev/tty 2>/dev/null || method_choice=""
    local host_method="tailscale"
    [[ "$method_choice" == "2" ]] && host_method="standard"

    if command -v jq &>/dev/null; then
      jq --arg name "$host_name" --arg addr "$host_addr" --arg method "$host_method" \
        '.hosts[$name] = {"address": $addr, "ssh_method": $method}' "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
    else
      python3 -c "
import json
with open('$CONFIG_FILE', 'r') as f: data = json.load(f)
data.setdefault('hosts', {})['$host_name'] = {'address': '$host_addr', 'ssh_method': '$host_method'}
with open('$CONFIG_FILE', 'w') as f: json.dump(data, f, indent=2)
"
    fi
    echo "  Added: $host_name -> $host_addr ($host_method)"

    echo "  Testing connection..."
    if ssh_exec "$host_addr" "$host_method" "echo ok" &>/dev/null; then
      echo "  Connected!"
    else
      echo "  Could not connect. Check address and SSH config."
    fi
    echo ""
  done

  # --- 3. Hooks ---
  echo "── Step 3/5: Claude Code Hooks ──"
  echo ""
  echo "  Hooks let Claude auto-detect new messages."
  echo "    - SessionStart:     check inbox when a session opens"
  echo "    - UserPromptSubmit: check before each response"
  echo "    - Stop:             check after each response, continue if new mail"
  echo ""

  local hooks_installed=false
  if [[ -f "$CLAUDE_SETTINGS" ]] && command -v jq &>/dev/null; then
    if jq -r '.hooks | .. | .command? // empty' "$CLAUDE_SETTINGS" 2>/dev/null | grep -q "cmail"; then
      echo "  Hooks are already installed."
      hooks_installed=true
    fi
  fi

  if [[ "$hooks_installed" == false ]]; then
    if [[ ! -f "$CLAUDE_SETTINGS" ]]; then
      echo "  No Claude Code settings found ($CLAUDE_SETTINGS)."
      echo "  Skipping — you can add hooks manually later."
    elif ! command -v jq &>/dev/null; then
      echo "  jq not found — needed to edit settings. Install jq and re-run setup."
    else
      read -r -p "  Install hooks now? [Y/n] " hook_confirm </dev/tty 2>/dev/null || hook_confirm="y"
      if [[ ! "$hook_confirm" =~ ^[Nn] ]]; then
        local session_start="$HOOKS_DIR/session-start.sh"
        local user_prompt="$HOOKS_DIR/user-prompt-submit.sh"
        local stop_hook="$HOOKS_DIR/stop.sh"
        local tmp="$CLAUDE_SETTINGS.tmp"

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

        echo "  Hooks installed!"
      else
        echo "  Skipped. Run 'cmail setup' again to install later."
      fi
    fi
  fi
  echo ""

  # --- 4. Status line ---
  echo "── Step 4/5: Status Line ──"
  echo ""
  echo "  Show inbox count in Claude Code's status line: (3) cmail"
  echo ""

  local statusline_done=false
  if [[ -f "$STATUSLINE_SCRIPT" ]]; then
    if grep -qF "cmail" "$STATUSLINE_SCRIPT" 2>/dev/null; then
      echo "  cmail is already in your status line."
      statusline_done=true
    fi
  fi

  if [[ "$statusline_done" == false ]]; then
    if [[ -f "$STATUSLINE_SCRIPT" ]]; then
      read -r -p "  Add cmail count to your existing status line? [Y/n] " sl_confirm </dev/tty 2>/dev/null || sl_confirm="y"
      if [[ ! "$sl_confirm" =~ ^[Nn] ]]; then
        cat >> "$STATUSLINE_SCRIPT" <<'CMAIL_EOF'

# cmail-statusline-start
_cmail_count=$(ls -1 "$HOME/.cmail/inbox/"*.json 2>/dev/null | wc -l | tr -d ' ')
if (( _cmail_count > 0 )); then
    _cmail_info=" \033[38;2;128;128;128m|\033[0m \033[1m(${_cmail_count})\033[22m cmail"
else
    _cmail_info=" \033[38;2;128;128;128m|\033[0m \033[38;2;128;128;128m(0) cmail\033[0m"
fi
# cmail-statusline-end
CMAIL_EOF
        echo "  Added! You may need to add \${_cmail_info} to your output line."
      else
        echo "  Skipped."
      fi
    else
      echo "  No statusline script found at $STATUSLINE_SCRIPT."
      echo "  See README for manual setup instructions."
    fi
  fi
  echo ""

  # --- 5. Watcher ---
  echo "── Step 5/5: Inbox Watcher ──"
  echo ""

  local watcher_running=false
  local pidfile="$COMMS_DIR/.watch.pid"
  if [[ -f "$pidfile" ]] && kill -0 "$(cat "$pidfile")" 2>/dev/null; then
    echo "  Watcher is running (PID: $(cat "$pidfile"))."
    watcher_running=true
  else
    echo "  Watcher is not running."
    read -r -p "  Start it now? [Y/n] " watch_confirm </dev/tty 2>/dev/null || watch_confirm="y"
    if [[ ! "$watch_confirm" =~ ^[Nn] ]]; then
      cmd_watch --daemon &
      sleep 1
      echo "  Watcher started."
      watcher_running=true
    fi
  fi

  # Check shell profile
  local SHELL_RC=""
  if [[ -f "$HOME/.zshrc" ]]; then
    SHELL_RC="$HOME/.zshrc"
  elif [[ -f "$HOME/.bashrc" ]]; then
    SHELL_RC="$HOME/.bashrc"
  fi

  if [[ -n "$SHELL_RC" ]]; then
    if grep -qF "cmail watch --daemon" "$SHELL_RC" 2>/dev/null; then
      echo "  Auto-start is configured in $SHELL_RC."
    else
      read -r -p "  Add auto-start to $SHELL_RC? [Y/n] " auto_confirm </dev/tty 2>/dev/null || auto_confirm="y"
      if [[ ! "$auto_confirm" =~ ^[Nn] ]]; then
        echo "" >> "$SHELL_RC"
        echo "# cmail: auto-start inbox watcher" >> "$SHELL_RC"
        echo 'command -v cmail &>/dev/null && cmail watch --daemon &>/dev/null &' >> "$SHELL_RC"
        echo "  Added to $SHELL_RC."
      fi
    fi
  fi
  echo ""

  # --- Summary ---
  echo "╔══════════════════════════════════════╗"
  echo "║          Setup complete!             ║"
  echo "╚══════════════════════════════════════╝"
  echo ""
  echo "  Identity:    $identity"

  # Count hosts
  local host_count=0
  if command -v jq &>/dev/null; then
    host_count=$(jq '.hosts | length' "$CONFIG_FILE" 2>/dev/null || echo 0)
  fi
  echo "  Hosts:       $host_count configured"

  if [[ "$hooks_installed" == true ]] || [[ -f "$CLAUDE_SETTINGS" ]] && command -v jq &>/dev/null && jq -r '.hooks | .. | .command? // empty' "$CLAUDE_SETTINGS" 2>/dev/null | grep -q "cmail"; then
    echo "  Hooks:       installed"
  else
    echo "  Hooks:       not installed"
  fi

  if [[ -f "$STATUSLINE_SCRIPT" ]] && grep -qF "cmail" "$STATUSLINE_SCRIPT" 2>/dev/null; then
    echo "  Status line: configured"
  else
    echo "  Status line: not configured"
  fi

  if [[ "$watcher_running" == true ]]; then
    echo "  Watcher:     running"
  else
    echo "  Watcher:     not running"
  fi

  echo ""
  echo "  Try: cmail send <host> \"hello from $identity\""
  echo ""
}

cmd_send() {
  ensure_config
  local host="" subject="" message="" in_reply_to="" thread_id=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --subject) subject="$2"; shift 2 ;;
      --in-reply-to) in_reply_to="$2"; shift 2 ;;
      --thread-id) thread_id="$2"; shift 2 ;;
      *)
        if [[ -z "$host" ]]; then
          host="$1"
        else
          message="$1"
        fi
        shift
        ;;
    esac
  done

  if [[ -z "$host" || -z "$message" ]]; then
    echo "Usage: cmail send <host> [--subject <subject>] <message>" >&2
    exit 1
  fi

  local address
  address="$(get_host_address "$host")"
  if [[ -z "$address" ]]; then
    address="$host"
  fi

  local method
  method="$(get_host_ssh_method "$host")"

  local identity
  identity="$(get_identity)"
  local msg_id
  msg_id="$(generate_uuid)"
  local timestamp
  timestamp="$(get_timestamp)"
  local file_timestamp
  file_timestamp="$(get_filename_timestamp)"
  local short_id="${msg_id:0:6}"
  local filename="${file_timestamp}-${identity}-${short_id}.json"

  [[ -z "$thread_id" ]] && thread_id="$msg_id"

  local json_msg
  if command -v jq &>/dev/null; then
    json_msg="$(jq -n \
      --arg id "$msg_id" \
      --arg from "$identity" \
      --arg to "$host" \
      --arg ts "$timestamp" \
      --arg subj "$subject" \
      --arg body "$message" \
      --arg reply "$in_reply_to" \
      --arg thread "$thread_id" \
      '{id: $id, from: $from, to: $to, timestamp: $ts, subject: $subj, body: $body, in_reply_to: ($reply | if . == "" then null else . end), thread_id: $thread}'
    )"
  else
    json_msg="$(python3 -c "
import json
msg = {
    'id': '$msg_id',
    'from': '$identity',
    'to': '$host',
    'timestamp': '$timestamp',
    'subject': '$subject',
    'body': $(python3 -c "import json; print(json.dumps('$message'))"),
    'in_reply_to': $(if [[ -n "$in_reply_to" ]]; then echo "'$in_reply_to'"; else echo "None"; fi),
    'thread_id': '$thread_id'
}
print(json.dumps(msg, indent=2))
")"
  fi

  echo "$json_msg" | ssh_pipe "$address" "$method" "mkdir -p ~/.cmail/inbox && cat > ~/.cmail/inbox/$filename && touch ~/.cmail/.has_unread"

  # Save to local outbox
  echo "$json_msg" > "$OUTBOX_DIR/$filename"

  echo "Message sent to $host (id: $msg_id)"
}

cmd_inbox() {
  ensure_config
  local if_new=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --if-new) if_new=true; shift ;;
      *) shift ;;
    esac
  done

  if [[ "$if_new" == true ]]; then
    if [[ ! -f "$UNREAD_MARKER" ]]; then
      echo "No new messages."
      return 0
    fi
  fi

  local files
  files="$(ls -1 "$INBOX_DIR"/*.json 2>/dev/null | sort -r)" || true

  if [[ -z "$files" ]]; then
    echo "Inbox is empty."
    return 0
  fi

  echo "=== Inbox ==="
  echo ""
  while IFS= read -r file; do
    local id from subject timestamp
    id="$(json_get "$file" '.id')"
    from="$(json_get "$file" '.from')"
    subject="$(json_get "$file" '.subject')"
    timestamp="$(json_get "$file" '.timestamp')"
    local short_id="${id:0:8}"
    local display_subject=""
    [[ -n "$subject" && "$subject" != "null" && "$subject" != "" ]] && display_subject=" — $subject"
    echo "[$short_id] $timestamp  from: $from$display_subject"
  done <<< "$files"
}

cmd_read() {
  ensure_config
  local target_id="$1"

  if [[ -z "$target_id" ]]; then
    echo "Usage: cmail read <message-id>" >&2
    exit 1
  fi

  local found=""
  for file in "$INBOX_DIR"/*.json; do
    [[ -f "$file" ]] || continue
    local id
    id="$(json_get "$file" '.id')"
    if [[ "$id" == "$target_id"* ]]; then
      found="$file"
      break
    fi
  done

  if [[ -z "$found" ]]; then
    echo "Message not found: $target_id" >&2
    exit 1
  fi

  local id from to timestamp subject body in_reply_to thread_id
  id="$(json_get "$found" '.id')"
  from="$(json_get "$found" '.from')"
  to="$(json_get "$found" '.to')"
  timestamp="$(json_get "$found" '.timestamp')"
  subject="$(json_get "$found" '.subject')"
  body="$(json_get "$found" '.body')"
  in_reply_to="$(json_get "$found" '.in_reply_to')"
  thread_id="$(json_get "$found" '.thread_id')"

  echo "=== Message ==="
  echo "ID:        $id"
  echo "From:      $from"
  echo "To:        $to"
  echo "Date:      $timestamp"
  [[ -n "$subject" && "$subject" != "null" ]] && echo "Subject:   $subject"
  [[ -n "$in_reply_to" && "$in_reply_to" != "null" ]] && echo "Reply-To:  $in_reply_to"
  [[ -n "$thread_id" && "$thread_id" != "null" ]] && echo "Thread:    $thread_id"
  echo "---"
  echo "$body"

  # Clear unread marker if no other unread messages
  # (Simple approach: remove marker, let watcher re-create if needed)
  rm -f "$UNREAD_MARKER"
}

cmd_reply() {
  local target_id="$1"
  shift || true
  local message=""
  local subject=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --subject) subject="$2"; shift 2 ;;
      *)
        message="$1"
        shift
        ;;
    esac
  done

  if [[ -z "$target_id" || -z "$message" ]]; then
    echo "Usage: cmail reply <message-id> [--subject <subject>] <message>" >&2
    exit 1
  fi

  # Find original message
  local found=""
  for file in "$INBOX_DIR"/*.json "$OUTBOX_DIR"/*.json; do
    [[ -f "$file" ]] || continue
    local id
    id="$(json_get "$file" '.id')"
    if [[ "$id" == "$target_id"* ]]; then
      found="$file"
      break
    fi
  done

  if [[ -z "$found" ]]; then
    echo "Original message not found: $target_id" >&2
    exit 1
  fi

  local orig_from orig_thread_id orig_subject
  orig_from="$(json_get "$found" '.from')"
  orig_thread_id="$(json_get "$found" '.thread_id')"
  orig_subject="$(json_get "$found" '.subject')"

  [[ -z "$subject" && -n "$orig_subject" && "$orig_subject" != "null" ]] && subject="Re: $orig_subject"

  cmd_send "$orig_from" --subject "$subject" --in-reply-to "$target_id" --thread-id "$orig_thread_id" "$message"
}

cmd_hosts() {
  ensure_config
  echo "=== Configured Hosts ==="
  echo ""

  local hosts_json
  if command -v jq &>/dev/null; then
    hosts_json="$(jq -r '.hosts | to_entries[] | "\(.key)\t\(.value.address)\t\(.value.ssh_method // "tailscale")"' "$CONFIG_FILE" 2>/dev/null)" || true
  else
    hosts_json="$(python3 -c "
import json
with open('$CONFIG_FILE') as f: data = json.load(f)
for name, info in data.get('hosts', {}).items():
    print(f\"{name}\t{info['address']}\t{info.get('ssh_method', 'tailscale')}\")
" 2>/dev/null)" || true
  fi

  if [[ -z "$hosts_json" ]]; then
    echo "No hosts configured. Run 'cmail setup' to add hosts."
    return 0
  fi

  while IFS=$'\t' read -r name address method; do
    local status="testing..."
    if ssh_exec "$address" "$method" "echo ok" &>/dev/null; then
      status="reachable"
    else
      status="unreachable"
    fi
    printf "%-20s %-35s %-12s %s\n" "$name" "$address" "$method" "$status"
  done <<< "$hosts_json"
}

notify_new_message() {
  local file="$1"
  local from=""
  [[ -f "$file" ]] && from="$(json_get "$file" '.from' 2>/dev/null)" || true
  touch "$UNREAD_MARKER"
  # Desktop notification (platform-dependent, silently skipped if unavailable)
  osascript -e "display notification \"New message from ${from:-unknown}\" with title \"cmail\"" 2>/dev/null \
    || notify-send "cmail" "New message from ${from:-unknown}" 2>/dev/null \
    || true
  echo "New message received: $(basename "$file")"
}

cmd_watch() {
  local daemon=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --daemon) daemon=true; shift ;;
      *) shift ;;
    esac
  done

  ensure_dirs

  # In daemon mode, silently exit if already running
  local pidfile="$COMMS_DIR/.watch.pid"
  if [[ "$daemon" == true ]]; then
    if [[ -f "$pidfile" ]] && kill -0 "$(cat "$pidfile")" 2>/dev/null; then
      return 0
    fi
    echo $$ > "$pidfile"
  fi

  if [[ "$daemon" != true ]]; then
    echo "Watching for new messages in $INBOX_DIR ..."
    echo "Press Ctrl+C to stop."
  fi

  if command -v fswatch &>/dev/null; then
    echo "(using fswatch)"
    fswatch -0 "$INBOX_DIR" | while IFS= read -r -d '' event; do
      [[ "$event" == *.json ]] || continue
      notify_new_message "$event"
    done
  elif command -v inotifywait &>/dev/null; then
    echo "(using inotifywait)"
    inotifywait -m -e create --format '%w%f' "$INBOX_DIR" | while IFS= read -r event; do
      [[ "$event" == *.json ]] || continue
      notify_new_message "$event"
    done
  else
    echo "(using polling — install fswatch or inotify-tools for instant detection)"
    local poll_interval="${CMAIL_POLL_INTERVAL:-5}"
    local known_files
    known_files="$(ls -1 "$INBOX_DIR"/*.json 2>/dev/null | sort)" || true
    while true; do
      sleep "$poll_interval"
      local current_files
      current_files="$(ls -1 "$INBOX_DIR"/*.json 2>/dev/null | sort)" || true
      if [[ "$current_files" != "$known_files" ]]; then
        # Find new files
        local new_files
        new_files="$(comm -13 <(echo "$known_files") <(echo "$current_files"))" || true
        while IFS= read -r file; do
          [[ -n "$file" ]] && notify_new_message "$file"
        done <<< "$new_files"
        known_files="$current_files"
      fi
    done
  fi
}

# --- Main ---

cmd="${1:-help}"
shift || true

# Auto-check deps on first run (skip for help/deps to avoid chicken-and-egg)
if [[ "$cmd" != "help" && "$cmd" != "--help" && "$cmd" != "-h" && "$cmd" != "deps" ]]; then
  check_deps
fi

case "$cmd" in
  setup)   cmd_setup "$@" ;;
  send)    cmd_send "$@" ;;
  inbox)   cmd_inbox "$@" ;;
  read)    cmd_read "$@" ;;
  reply)   cmd_reply "$@" ;;
  hosts)   cmd_hosts "$@" ;;
  watch)   cmd_watch "$@" ;;
  deps)    cmd_deps "$@" ;;
  help|--help|-h)
    echo "cmail — File-based messaging over Tailscale SSH"
    echo ""
    echo "Commands:"
    echo "  setup                          Configure identity and hosts"
    echo "  send <host> [--subject s] msg  Send a message"
    echo "  inbox [--if-new]               List inbox messages"
    echo "  read <id>                      Read a message"
    echo "  reply <id> [--subject s] msg   Reply to a message"
    echo "  hosts                          List hosts + test connectivity"
    echo "  watch                          Watch for new messages"
    echo "  deps                           Check and install dependencies"
    echo "  help                           Show this help"
    ;;
  *)
    echo "Unknown command: $cmd" >&2
    echo "Run 'cmail help' for usage." >&2
    exit 1
    ;;
esac

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
  local identity
  identity="$(json_get "$CONFIG_FILE" '.identity')"
  echo "=== cmail setup ==="
  echo ""
  echo "Current identity: $identity"
  read -r -p "New identity (Enter to keep current): " new_identity
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
    echo "Identity set to: $new_identity"
  fi

  echo ""
  echo "Add a host (leave name blank to skip):"
  while true; do
    read -r -p "  Host name: " host_name
    [[ -z "$host_name" ]] && break
    read -r -p "  Address (hostname or IP): " host_addr
    [[ -z "$host_addr" ]] && { echo "  Address required, skipping."; continue; }
    read -r -p "  SSH method [tailscale/standard] (default: tailscale): " host_method
    host_method="${host_method:-tailscale}"

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
    echo "  Added host: $host_name -> $host_addr ($host_method)"
    echo ""

    echo "  Testing connectivity..."
    if ssh_exec "$host_addr" "$host_method" "echo ok" &>/dev/null; then
      echo "  Connection successful!"
    else
      echo "  Connection failed. Check address and SSH configuration."
    fi
    echo ""
  done
  echo "Setup complete."
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

cmd_watch() {
  ensure_dirs
  echo "Watching for new messages in $INBOX_DIR ..."
  echo "Press Ctrl+C to stop."

  local watch_cmd=""
  if command -v fswatch &>/dev/null; then
    watch_cmd="fswatch"
  elif command -v inotifywait &>/dev/null; then
    watch_cmd="inotifywait"
  else
    echo "Error: Neither fswatch (macOS) nor inotifywait (Linux) found." >&2
    echo "Install with: brew install fswatch (macOS) or apt install inotify-tools (Linux)" >&2
    exit 1
  fi

  if [[ "$watch_cmd" == "fswatch" ]]; then
    fswatch -0 "$INBOX_DIR" | while IFS= read -r -d '' event; do
      [[ "$event" == *.json ]] || continue
      touch "$UNREAD_MARKER"
      # Desktop notification (macOS)
      local from=""
      [[ -f "$event" ]] && from="$(json_get "$event" '.from' 2>/dev/null)" || true
      osascript -e "display notification \"New message from ${from:-unknown}\" with title \"cmail\"" 2>/dev/null || true
      echo "New message received: $(basename "$event")"
    done
  else
    inotifywait -m -e create --format '%w%f' "$INBOX_DIR" | while IFS= read -r event; do
      [[ "$event" == *.json ]] || continue
      touch "$UNREAD_MARKER"
      # Desktop notification (Linux)
      local from=""
      [[ -f "$event" ]] && from="$(json_get "$event" '.from' 2>/dev/null)" || true
      notify-send "cmail" "New message from ${from:-unknown}" 2>/dev/null || true
      echo "New message received: $(basename "$event")"
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

# cmail 📬

**File-based peer-to-peer messaging for Claude Code instances (and humans) across a Tailscale network.**

Send messages between Claude instances running on different machines by SSH-ing to remote hosts and writing JSON files to their `~/.cmail/inbox/`. Simple, decentralized, and works anywhere you have SSH access.

---

## What It Is

cmail is a Claude Code skill that enables messaging between:
- Claude instance → Claude instance (cross-machine coordination)
- Human → Claude instance (send tasks to a persistent Claude on a server)
- Human → Human (minimal CLI messaging)

**How it works:** Each machine maintains a `~/.cmail/` directory. Sending a message = SSH to the remote machine and write a JSON file. Receiving = read local inbox files. No server, no complexity.

---

## Prerequisites

### All Platforms
- **Tailscale** (recommended) or standard SSH access between machines
- **Bash** 4.0+ (ships with macOS and most Linux distros)
- **jq** (recommended but optional — fallback uses Python)
- **Python 3** (for UUID/timestamp fallback when native tools unavailable)

### Platform-Specific

#### macOS
✅ Everything works out of the box except:
- `jq` (install via `brew install jq` — recommended)
- `fswatch` for the watcher (install via `brew install fswatch`)

#### Linux (Desktop)
✅ Most distros include everything except:
- `jq` (install via `apt install jq` or `yum install jq`)
- `inotify-tools` for the watcher (install via `apt install inotify-tools` or `yum install inotify-tools`)

#### Linux (Server/Headless)
✅ Same as desktop, but notifications won't work (requires `notify-send` + a running display server). The watcher still works — it just skips the notification step.

#### Windows (WSL)
✅ Works in WSL (Ubuntu, Debian, etc.) with the same requirements as Linux. Native Windows support is not currently available.

⚠️ **Known WSL limitation:** `notify-send` requires a running X server or Windows notification bridge. The watcher will work but skip notifications.

---

## Installation

### 1. Clone the repo
```bash
git clone https://github.com/ORDIGSEC/claudeComms.git
cd claudeComms
```

### 2. Run the installer
```bash
./install.sh
```

This will:
- Symlink `skills/cmail/` → `~/.claude/skills/cmail/`
- Create `~/.cmail/inbox/` and `~/.cmail/outbox/`
- Generate a default `~/.cmail/config.json` with your hostname as identity
- Make the main script executable

### 3. Repeat on every machine
Run the installer on each machine where you want cmail available (both sending and receiving).

---

## Setup

### Configure Identity and Hosts

Run setup on each machine:
```bash
~/.claude/skills/cmail/scripts/cmail.sh setup
```

This will:
1. Set your identity (defaults to hostname — e.g., `matt-macbook`, `dev-server`)
2. Add remote hosts you want to message:
   - **Host name:** Friendly name (e.g., `dev-server`, `matt-laptop`)
   - **Address:** Tailscale hostname (e.g., `dev-server.tail1234.ts.net`) or IP
   - **SSH method:** `tailscale` (uses `tailscale ssh`) or `standard` (regular SSH)
3. Test connectivity to each host

**Example session:**
```
=== cmail setup ===

Current identity: matt-macbook
New identity (Enter to keep current):

Add a host (leave name blank to skip):
  Host name: dev-server
  Address (hostname or IP): dev-server.tail1234.ts.net
  SSH method [tailscale/standard] (default: tailscale):
  Added host: dev-server -> dev-server.tail1234.ts.net (tailscale)

  Testing connectivity...
  Connection successful!

  Host name:
Setup complete.
```

### SSH Method Notes

**Tailscale SSH (default):**
- Uses `tailscale ssh <host>` — no SSH keys or password needed
- Requires Tailscale SSH enabled on both machines
- Automatically falls back to standard SSH if Tailscale SSH fails

**Standard SSH:**
- Uses regular `ssh <host>` — requires SSH keys or password
- Works on any machine with SSH access (no Tailscale needed)
- Useful for non-Tailscale hosts or when Tailscale SSH is disabled

The script auto-detects failures and updates the config to use standard SSH on future attempts.

---

## Usage

### Send a Message
```bash
cmail send dev-server "Found the bug — it's in auth.py line 42"
```

With a subject line:
```bash
cmail send dev-server --subject "Bug Report" "auth.py has a null check issue"
```

### Check Inbox
List all messages (newest first):
```bash
cmail inbox
```

Check only if there are new messages (efficient — checks marker file):
```bash
cmail inbox --if-new
```

### Read a Message
```bash
cmail read a1b2c3d4
```
(You can use the short ID from `inbox` output — first 6-8 characters of the UUID)

### Reply to a Message
```bash
cmail reply a1b2c3d4 "Thanks, I'll take a look"
```

Preserves threading (uses the same `thread_id` as the original message).

### List Hosts
```bash
cmail hosts
```
Shows all configured hosts and tests connectivity.

### Watch for New Messages
```bash
cmail watch
```

Starts a background watcher that:
- Monitors `~/.cmail/inbox/` for new files
- Creates a `.has_unread` marker when messages arrive
- Sends a desktop notification (platform-dependent)

**Platform differences:**
- **macOS:** Uses `fswatch` + `osascript` for notifications
- **Linux desktop:** Uses `inotifywait` + `notify-send`
- **Linux server:** Uses `inotifywait` but skips notifications

Run in the background:
```bash
cmail watch &
```

Or add to your shell startup (`~/.bashrc`, `~/.zshrc`):
```bash
~/.claude/skills/cmail/scripts/cmail.sh watch &>/dev/null &
```

---

## How It Works as a Claude Code Skill

The skill definition (`SKILL.md`) tells Claude Code to invoke `cmail.sh` when you mention:
- "cmail" / "check cmail"
- "send to"
- "check inbox" / "check messages"
- "communicate with"
- "reply to"
- Inter-agent coordination requests

**Example interactions:**
- **You:** "Check your cmail"
  - **Claude:** Runs `cmail inbox --if-new`
- **You:** "Send a cmail to dev-server asking for the latest build status"
  - **Claude:** Runs `cmail send dev-server "What's the latest build status?"`
- **You:** "Are there any new cmails?"
  - **Claude:** Runs `cmail inbox --if-new`
- **You:** "Reply to that cmail saying it's fixed"
  - **Claude:** Runs `cmail reply <id> "Build is fixed and deployed"`

---

## Directory Structure

```
~/.cmail/
  inbox/                              # Incoming messages (JSON files)
  outbox/                             # Sent messages (local log)
  config.json                         # Identity + known hosts
  .has_unread                         # Marker file (created by watcher)
```

### Message Format

Messages are JSON files named `YYYYMMDDTHHMMSS.sssZ-<from>-<short-uuid>.json`:

```json
{
  "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "from": "matt-macbook",
  "to": "dev-server",
  "timestamp": "2026-02-15T10:30:00.000Z",
  "subject": "Bug Report",
  "body": "Found the bug — it's in auth.py line 42",
  "in_reply_to": null,
  "thread_id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
}
```

---

## Platform Compatibility Notes

### Known Issues and Workarounds

#### 1. **UUID Generation**
- **macOS/BSD:** Uses `uuidgen` (built-in)
- **Linux:** Uses `/proc/sys/kernel/random/uuid` (built-in)
- **Fallback:** Python `uuid.uuid4()` (requires Python 3)

**No changes needed** — script handles all three methods.

#### 2. **Timestamp Formatting**
- **GNU date (Linux):** `date -u +%Y-%m-%dT%H:%M:%S.000Z` works
- **BSD date (macOS):** Same command works
- **Busybox/Alpine:** May fail — fallback uses Python `datetime`

**No changes needed** — script handles fallback.

#### 3. **File Watching**
- **macOS:** Requires `fswatch` (`brew install fswatch`)
- **Linux:** Requires `inotify-tools` (`apt install inotify-tools`)
- **BSD/other:** Not currently supported

**To fix:** Add support for `kqueue` on BSD or polling fallback for unsupported systems.

#### 4. **Notifications**
- **macOS:** `osascript -e 'display notification ...'` (built-in)
- **Linux desktop:** `notify-send` (requires `libnotify-bin`)
- **Linux server/WSL:** No notification support (script silently skips)

**To fix:** Add Windows notification support for WSL via PowerShell or `wsl-notify-send`.

#### 5. **SSH Compatibility**
- **Tailscale SSH:** Requires Tailscale 1.32+ on both machines
- **Standard SSH:** Works everywhere but requires key-based auth or password

**No changes needed** — auto-fallback handles this.

#### 6. **JSON Parsing**
- **With jq:** Fast and reliable
- **Without jq:** Python fallback (slower but functional)

**Recommendation:** Install `jq` for best performance.

---

## Troubleshooting

### "Connection failed" when testing hosts
- Check Tailscale is running: `tailscale status`
- Verify SSH access: `tailscale ssh <host> echo ok` or `ssh <host> echo ok`
- Confirm remote machine has `~/.cmail/` directory

### "Neither fswatch nor inotifywait found"
- **macOS:** `brew install fswatch`
- **Linux:** `apt install inotify-tools` or `yum install inotify-tools`

### "Message not found" when reading
- Use the short ID from `inbox` output (first 6-8 characters)
- Check the message exists: `ls ~/.cmail/inbox/*.json`

### Notifications not working
- **macOS:** Should work out of the box (uses AppleScript)
- **Linux desktop:** Install `libnotify-bin`: `apt install libnotify-bin`
- **Linux server/WSL:** Notifications not supported (expected behavior)

### Claude isn't triggering the skill
- Verify skill is installed: `ls -la ~/.claude/skills/cmail`
- Check Claude's skill auto-loading is enabled (default in Claude Code 1.0+)
- Try explicitly: "Use the cmail skill to check my inbox"

---

## Examples

### Scenario 1: Human sends task to remote Claude
On your laptop:
```bash
cmail send dev-server --subject "Deploy Request" "Please deploy the latest main branch to staging"
```

On the server, Claude checks messages:
```bash
cmail inbox --if-new
cmail read a1b2c3d4
```

Claude processes the request and replies:
```bash
cmail reply a1b2c3d4 "Deployed to staging. Build #428 is live."
```

### Scenario 2: Claude instances coordinate
Claude on `matt-laptop` is working on a feature. Claude on `dev-server` finishes testing:
```bash
cmail send matt-laptop "Tests passed — auth refactor is ready to merge"
```

Claude on `matt-laptop` sees the message:
```bash
cmail inbox --if-new
# Shows the new message from dev-server
```

### Scenario 3: Background watcher setup
On a server running Claude 24/7:
```bash
# Add to ~/.bashrc or startup script
~/.claude/skills/cmail/scripts/cmail.sh watch &>/dev/null &
```

Now any message sent to that server triggers the `.has_unread` marker, and Claude can efficiently check with `inbox --if-new`.

---

## Advanced Configuration

### Custom Identity
Edit `~/.cmail/config.json` manually or re-run `setup`:
```json
{
  "identity": "my-custom-name",
  "hosts": { ... }
}
```

### Multiple SSH Methods
Mix Tailscale and standard SSH in the same config:
```json
{
  "identity": "matt-macbook",
  "hosts": {
    "dev-server": {
      "address": "dev-server.tail1234.ts.net",
      "ssh_method": "tailscale"
    },
    "old-box": {
      "address": "192.168.1.100",
      "ssh_method": "standard"
    }
  }
}
```

### Direct Addressing
Send to a raw address without adding to config:
```bash
cmail send dev-server.tail1234.ts.net "Quick test message"
```

---

## Contributing

Issues and PRs welcome at [github.com/ORDIGSEC/claudeComms](https://github.com/ORDIGSEC/claudeComms).

**Priority improvements:**
1. BSD/kqueue support for `watch` command
2. Windows native support (non-WSL)
3. WSL notification bridge
4. Thread view command (`cmail thread <id>`)
5. Message archival/cleanup utilities

---

## License

MIT — see LICENSE file.

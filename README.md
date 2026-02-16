# claudeComms

File-based messaging for Claude instances across a Tailscale network.

Multiple people working in the same repo often have Claude instances running on different machines. claudeComms lets those instances message each other — to share findings, coordinate work, or receive notes from humans.

## How It Works

Each machine has a `~/.claudecomms/` directory. Sending a message = SSH into the remote machine and write a JSON file to its inbox. Receiving = read local inbox files.

```
~/.claudecomms/
  inbox/          # incoming messages
  outbox/         # sent message log
  config.json     # identity + known hosts
  .has_unread     # marker file for new messages
```

## Install

```bash
git clone <this-repo> ~/projects/claudeComms
cd ~/projects/claudeComms
bash install.sh
```

This symlinks the skill into `~/.claude/skills/` and initializes the messaging directories.

## Setup

```bash
~/.claude/skills/claudecomms/scripts/claudecomms.sh setup
```

This walks you through setting your identity and adding remote hosts. Each host needs a friendly name, a Tailscale address (hostname or IP), and an SSH method (`tailscale` or `standard`).

## Usage

```bash
CC=~/.claude/skills/claudecomms/scripts/claudecomms.sh

# Send a message
$CC send dev-server "Found the bug in auth.py"

# Send with a subject
$CC send dev-server --subject "Bug report" "Auth fails on line 42"

# Check inbox (zero-cost check for new messages)
$CC inbox --if-new

# List all messages
$CC inbox

# Read a specific message
$CC read <message-id>

# Reply to a message (preserves thread)
$CC reply <message-id> "Thanks, I'll fix it"

# List hosts and test connectivity
$CC hosts

# Watch for new messages (background, with desktop notifications)
$CC watch &
```

## Config

`~/.claudecomms/config.json`:

```json
{
  "identity": "matt-macbook",
  "hosts": {
    "dev-server": {
      "address": "dev-server.tail1234.ts.net",
      "ssh_method": "tailscale"
    },
    "old-box": {
      "address": "100.64.1.5",
      "ssh_method": "standard"
    }
  }
}
```

- **identity**: Your machine's name (defaults to hostname)
- **hosts**: Map of friendly names to addresses. `ssh_method` is `tailscale` (default, uses `tailscale ssh`) or `standard` (regular `ssh`)

## Message Format

```json
{
  "id": "uuid-v4",
  "from": "matt-macbook",
  "to": "dev-server",
  "timestamp": "2026-02-15T10:30:00.000Z",
  "subject": "optional subject line",
  "body": "the actual message content",
  "in_reply_to": null,
  "thread_id": "uuid-of-first-message-in-thread"
}
```

## Real-time Notifications

Run `claudecomms watch` to get notified when new messages arrive:

- Uses `fswatch` on macOS, `inotifywait` on Linux
- Touches `.has_unread` marker on new messages
- Sends desktop notifications (macOS `osascript`, Linux `notify-send`)

Install the watcher dependency:
- macOS: `brew install fswatch`
- Linux: `apt install inotify-tools`

## Requirements

- Bash 4+
- Tailscale (for `tailscale ssh`) or standard SSH access between machines
- `jq` (recommended) or `python3` (fallback for JSON handling)
- `fswatch` or `inotifywait` (optional, for `watch` command)

## As a Claude Code Skill

Once installed, Claude Code will automatically use claudeComms when you say things like:
- "Check my messages"
- "Send a message to dev-server"
- "Reply to that message"
- "Are there any new messages?"

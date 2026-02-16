# cmail Design — File-based Messaging over Tailscale SSH

## Context

Multiple people working in the same repo often have Claude instances running on different machines across a Tailscale network (4-10 machines). There's no way for these Claude instances to message each other — to share findings, coordinate work, or receive notes from a human sending to a persistent Claude on a remote server.

No existing tool fills this gap. Claude Code's built-in Agent Teams is same-machine only with a hub-and-spoke hierarchy. This project creates a simple, decentralized, peer-to-peer messaging system for Claude instances (and eventually Ollama models) across a Tailscale network.

## Architecture

**Core idea:** Each machine has a `~/.cmail/` directory. Sending a message = SSH into the remote machine and write a JSON file to its inbox. Receiving = read local inbox files.

**Packaged as:** A single Claude Code skill with embedded bash logic.

```
~/.cmail/
  inbox/                              # incoming messages
    20260215T103000.000Z-matt-macbook-a1b2c3.json
  outbox/                             # sent messages (local log)
    20260215T103000.000Z-dev-server-a1b2c3.json
  config.json                         # identity + known hosts
  .has_unread                         # marker file for new message detection
```

### Message Format

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

### Config

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

Identity defaults to `$(hostname)`. Hosts map friendly names to Tailscale hostnames/IPs. `ssh_method` is `"tailscale"` (default) or `"standard"` for fallback.

## Commands

| Command | Description |
|---------|-------------|
| `cmail send <host> <message>` | SSH to remote, write message file to their inbox |
| `cmail send <host> --subject <subj> <message>` | Send with subject line |
| `cmail inbox` | List all messages (newest first) |
| `cmail inbox --if-new` | List only if `.has_unread` marker exists (zero-cost check) |
| `cmail read <id>` | Read a specific message, remove from unread |
| `cmail reply <id> <message>` | Reply preserving thread_id |
| `cmail hosts` | List configured hosts + test connectivity |
| `cmail setup` | Set identity, add hosts, test SSH connections |
| `cmail watch` | Background watcher: creates `.has_unread` marker + desktop notification on new messages |

## Con Mitigations

### Con 1: No real-time push — Marker file + watcher

- `cmail watch` runs `fswatch` (macOS) or `inotifywait` (Linux) on `~/.cmail/inbox/`
- On new file: touches `~/.cmail/.has_unread` and sends desktop notification (`osascript` on macOS, `notify-send` on Linux)
- `cmail inbox --if-new` checks the marker file — returns nothing if no new messages (zero-cost)
- `cmail read` clears the marker when all messages have been read
- Can be started as `cmail watch &` in background

### Con 2: Requires Tailscale SSH — SSH method fallback

- Per-host `ssh_method` config: `"tailscale"` (uses `tailscale ssh`) or `"standard"` (uses regular `ssh`)
- `cmail send` tries the configured method; if `tailscale` fails, automatically falls back to `standard` ssh using the same address
- `cmail setup` tests connectivity and auto-detects the best method per host
- Raw Tailscale hostnames/IPs work without config entries

### Con 3: No guaranteed ordering — Timestamp filenames

- Files named `YYYYMMDDTHHMMSS.sssZ-<from>-<short-uuid>.json`
- Lexicographic sort = chronological order
- `inbox` command sorts by filename by default
- Thread view groups by `thread_id`, sorted by timestamp within thread

## Skill Structure

```
~/.claude/skills/cmail/
  SKILL.md              # Skill definition — tells Claude when/how to use cmail
  scripts/
    cmail.sh      # The main bash script with all subcommands
```

## Verification

1. **Setup test:** Run `cmail setup`, configure identity and at least one host
2. **Send test:** `cmail send <host> "test message"` — verify file appears in remote inbox
3. **Inbox test:** `cmail inbox` on receiving machine — verify message listed
4. **Read test:** `cmail read <id>` — verify message content displayed
5. **Reply test:** `cmail reply <id> "reply message"` — verify thread_id preserved
6. **Watcher test:** `cmail watch &`, then send a message — verify `.has_unread` created and notification appears
7. **if-new test:** `cmail inbox --if-new` — verify it returns messages only when marker exists
8. **Fallback test:** Configure a host with `ssh_method: tailscale`, disable Tailscale SSH, verify fallback to standard SSH
9. **Skill test:** Install skill, start Claude Code, ask it to "check my messages" — verify it invokes `cmail inbox`

---
name: cmail
description: Send and receive messages between Claude Code instances across machines on a Tailscale network. File-based messaging with inbox monitoring, threading, and an optional auto-respond agent.
license: Complete terms in LICENSE.txt
allowed-tools:
  - Bash(cmail *)
  - Bash(~/.claude/skills/cmail/scripts/cmail.sh *)
  - Bash(rm -f ~/.cmail/inbox/*.json *)
  - Bash(rm -f ~/.cmail/.has_unread)
  - Bash(rm -f ~/.cmail/.last_stop_check)
  - Bash(ls ~/.cmail/inbox/*)
  - Bash(tailscale ssh *)
  - Bash(claude --print *)
---

# cmail — Claude Mail over Tailscale SSH

Send and receive messages between Claude instances (and humans) across machines on a Tailscale network.

## Installation

```bash
./install.sh
```

The installer symlinks this skill into `~/.claude/skills/`, puts `cmail` on your PATH, configures Claude Code hooks/permissions, and starts the inbox watcher. Requires [Tailscale](https://tailscale.com/) for networking and `jq` for JSON handling.

## Quick Reference

| Command | Description |
|---------|-------------|
| `cmail send <host> "<message>"` | Send a message |
| `cmail send <host> --subject "<subj>" "<message>"` | Send with subject |
| `cmail inbox show` | List all messages (newest first) |
| `cmail inbox show --if-new` | List only if new messages exist |
| `cmail inbox clear` | Delete all messages (with confirmation) |
| `cmail read <id>` | Read a specific message |
| `cmail reply <id> "<message>"` | Reply preserving thread |
| `cmail hosts` | List hosts + test connectivity |
| `cmail setup` | Configure identity and hosts |
| `cmail watch` | Background watcher for new messages |
| `cmail deps` | Check and install dependencies |

## Usage Examples

**Check your cmail (zero-cost, do this periodically):**
```bash
cmail inbox show --if-new
```

**Send cmail to another machine:**
```bash
cmail send dev-server "Found the bug — it's in auth.py line 42"
```

**Reply to a cmail:**
```bash
cmail reply <message-id> "Thanks, I'll take a look"
```

## Message Format

Messages are JSON files stored in `~/.cmail/inbox/` with fields: `id`, `from`, `to`, `timestamp`, `subject`, `body`, `in_reply_to`, `thread_id`.

## Behavior Guidelines

- When asked to "check cmail" or "check inbox", run `inbox show --if-new` first for efficiency.
- When sending cmail, keep messages concise and actionable.
- When replying, always use the `reply` command to preserve threading.
- If setup hasn't been run yet, run `setup` first.

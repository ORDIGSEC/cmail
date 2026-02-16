---
name: cmail
description: Use when you need to send messages to or check messages from other Claude instances or humans on the Tailscale network. Triggers: "cmail", "message", "send to", "check inbox", "check messages", "check cmail", "communicate with", inter-agent coordination, "reply to".
---

# cmail — Claude Mail over Tailscale SSH

Send and receive messages between Claude instances (and humans) across machines on a Tailscale network.

## Quick Reference

| Command | Description |
|---------|-------------|
| `~/.claude/skills/cmail/scripts/cmail.sh send <host> "<message>"` | Send a message |
| `~/.claude/skills/cmail/scripts/cmail.sh send <host> --subject "<subj>" "<message>"` | Send with subject |
| `~/.claude/skills/cmail/scripts/cmail.sh inbox` | List all messages (newest first) |
| `~/.claude/skills/cmail/scripts/cmail.sh inbox --if-new` | List only if new messages exist |
| `~/.claude/skills/cmail/scripts/cmail.sh read <id>` | Read a specific message |
| `~/.claude/skills/cmail/scripts/cmail.sh reply <id> "<message>"` | Reply preserving thread |
| `~/.claude/skills/cmail/scripts/cmail.sh hosts` | List hosts + test connectivity |
| `~/.claude/skills/cmail/scripts/cmail.sh setup` | Configure identity and hosts |
| `~/.claude/skills/cmail/scripts/cmail.sh watch` | Background watcher for new messages |
| `~/.claude/skills/cmail/scripts/cmail.sh deps` | Check and install dependencies |

## Usage Examples

**Check your cmail (zero-cost, do this periodically):**
```bash
~/.claude/skills/cmail/scripts/cmail.sh inbox --if-new
```

**Send cmail to another machine:**
```bash
~/.claude/skills/cmail/scripts/cmail.sh send dev-server "Found the bug — it's in auth.py line 42"
```

**Reply to a cmail:**
```bash
~/.claude/skills/cmail/scripts/cmail.sh reply <message-id> "Thanks, I'll take a look"
```

## Message Format

Messages are JSON files stored in `~/.cmail/inbox/` with fields: `id`, `from`, `to`, `timestamp`, `subject`, `body`, `in_reply_to`, `thread_id`.

## Behavior Guidelines

- When asked to "check cmail" or "check inbox", run `inbox --if-new` first for efficiency.
- When sending cmail, keep messages concise and actionable.
- When replying, always use the `reply` command to preserve threading.
- If setup hasn't been run yet, run `setup` first.

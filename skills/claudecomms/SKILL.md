---
name: claudecomms
description: Use when you need to send messages to or check messages from other Claude instances or humans on the Tailscale network. Triggers: "message", "send to", "check inbox", "check messages", "communicate with", inter-agent coordination, "reply to".
---

# claudeComms — File-based Messaging over Tailscale SSH

Send and receive messages between Claude instances (and humans) across machines on a Tailscale network.

## Quick Reference

| Command | Description |
|---------|-------------|
| `~/.claude/skills/claudecomms/scripts/claudecomms.sh send <host> "<message>"` | Send a message |
| `~/.claude/skills/claudecomms/scripts/claudecomms.sh send <host> --subject "<subj>" "<message>"` | Send with subject |
| `~/.claude/skills/claudecomms/scripts/claudecomms.sh inbox` | List all messages (newest first) |
| `~/.claude/skills/claudecomms/scripts/claudecomms.sh inbox --if-new` | List only if new messages exist |
| `~/.claude/skills/claudecomms/scripts/claudecomms.sh read <id>` | Read a specific message |
| `~/.claude/skills/claudecomms/scripts/claudecomms.sh reply <id> "<message>"` | Reply preserving thread |
| `~/.claude/skills/claudecomms/scripts/claudecomms.sh hosts` | List hosts + test connectivity |
| `~/.claude/skills/claudecomms/scripts/claudecomms.sh setup` | Configure identity and hosts |
| `~/.claude/skills/claudecomms/scripts/claudecomms.sh watch` | Background watcher for new messages |

## Usage Examples

**Check for new messages (zero-cost, do this periodically):**
```bash
~/.claude/skills/claudecomms/scripts/claudecomms.sh inbox --if-new
```

**Send a message to another machine:**
```bash
~/.claude/skills/claudecomms/scripts/claudecomms.sh send dev-server "Found the bug — it's in auth.py line 42"
```

**Reply to a message:**
```bash
~/.claude/skills/claudecomms/scripts/claudecomms.sh reply <message-id> "Thanks, I'll take a look"
```

## Message Format

Messages are JSON files stored in `~/.claudecomms/inbox/` with fields: `id`, `from`, `to`, `timestamp`, `subject`, `body`, `in_reply_to`, `thread_id`.

## Behavior Guidelines

- When asked to "check messages" or "check inbox", run `inbox --if-new` first for efficiency.
- When sending messages, keep them concise and actionable.
- When replying, always use the `reply` command to preserve threading.
- If setup hasn't been run yet, run `setup` first.

# Swoosh UX

## Design Principle

Swoosh preserves **Hermes-style terminal power-user feel** while adding native Mac agent capabilities.

The terminal is first-class. Swoosh.app enhances but never replaces it.

## Interactive Shell

```
swoosh              → opens interactive REPL (default command)
swoosh ask "..."    → one-shot question
swoosh setup quick  → guided onboarding
swoosh doctor       → diagnostics
```

### Banner

On launch, the shell shows:

```
╔═══════════════════════════════════════════════╗
║                   Swoosh                      ║
║     Swift-native agent runtime for macOS      ║
╚═══════════════════════════════════════════════╝

  Model:        not configured (MLX-capable: 7B, 13B)
  Mode:         interactive
  Memory:       4 approved, 0 pending
  Permissions:  safe
  State plane:  SQLite
  Session:      default

  Type /help for commands, or ask a question.
```

### Slash Commands

| Command | Category | Description |
|---------|----------|-------------|
| /help | General | List all commands |
| /exit | General | Exit shell |
| /clear | General | Clear screen |
| /status | General | Show session status |
| /model | Agent | Show/change model |
| /tools | Agent | List available tools |
| /sessions | Agent | Manage chat sessions |
| /why | Agent | Explain context used in last response |
| /repeat | Agent | Turn last task into workflow draft |
| /scout | Personalization | Run environment scan |
| /vault | Personalization | Manage memory candidates |
| /permissions | System | Show permission profile |
| /firewall | System | Show firewall rules |
| /local | Development | Local model/MLX status |
| /db | Development | SwooshDB/SpacetimeDB status |

### Aliases

| Alias | Resolves to |
|-------|-------------|
| /h, /? | /help |
| /q, /quit | /exit |
| /s | /status |
| /m | /model |
| /t | /tools |
| /r | /repeat |
| /v, /memory | /vault |
| /p, /perms | /permissions |
| /fw | /firewall |

## Non-goals for UX

- No Electron wrapper
- No web-only interface
- No chat-only mode (slash commands are essential)
- No auto-executing workflows without confirmation
- No hidden data collection

# Swoosh Demo Script — Private Alpha

## Prerequisites

```bash
swift build --target SwooshCLI
```

## Demo

### 1. Start the interactive shell

```bash
swoosh
```

Banner shows:

```
Swoosh
Mode: interactive
Memory: 0 approved, 0 pending
Permissions: safe
```

### 2. Explore commands

```
/help
```

Shows all 15 commands organized by category.

### 3. Run Scout scan

```bash
# In a separate terminal (or use the CLI directly):
swoosh scout run --depth minimal
```

Output shows detected apps (Xcode, Cursor, Blender, etc.) and generates 4 memory candidates.

### 4. Review memory candidates

```bash
swoosh memory list
```

Shows pending candidates with confidence scores:

```
1. [profile] User is a developer. Development tools: Xcode, Cursor.
   confidence: 90% | sensitivity: low

2. [profile] User works with creative/design tools: Blender.
   confidence: 85% | sensitivity: low
```

### 5. Approve memories

```bash
swoosh memory approve
```

```
✓ Approved 4 memory candidate(s).
```

### 6. View approved memories

```bash
swoosh memory show
```

### 7. Ask a question (one-shot)

```bash
swoosh ask "What should we build next?"
```

Shows:

```
Context: approved memories and setup summary are loaded.
Assistant: <provider response, or local diagnostic response when no provider is configured>
```

### 8. Check the audit trail

```bash
sqlite3 ~/.swoosh/state.db "SELECT event_type, details FROM audit_events"
```

Shows every scan and approval event.

### 9. Interactive shell commands

```
/vault           → memory vault status
/permissions     → permission profile
/why             → context transparency (pending 0.3A)
/repeat          → workflow generator (pending 0.5A)
/db              → ActantDB ledger status
```

### 10. Run diagnostics

```bash
swoosh doctor
```

## What works now

- Interactive shell with 15 slash commands
- Scout scan with real hardware detection
- Memory candidate → approval → vault lifecycle
- SQLite persistence with audit trail
- ActantDB event ledger (sessions + audit) wired via SwooshActantBackend
- `swoosh ask` one-shot with memory context detection

## What's next (0.3A)

- Agent kernel wired to approved memories
- Model router (local MLX + cloud)
- /why context transparency
- Session persistence

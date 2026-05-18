# Swoosh v0 Architecture

## Process model

```
Swoosh.app ──┐
swoosh CLI ──┤── SQLite (state.db) ──── Keychain (secrets)
swooshd ─────┤
             └── actantdb serve (subprocess) ── event ledger / replay / approvals
```

v0 keeps **SQLite** at `~/.swoosh/state.db` for memories, setup reports, and
permissions (no server-side query endpoint exists for these yet on ActantDB).

**Session messages, tool calls, and response-audit records** route through
**ActantDB** — an event-sourced backend with hash-chained events, replay,
and Studio. `swooshd` spawns `actantdb serve --db ~/.swoosh/actant.db --bind
127.0.0.1:<port>` as a child process; `SwooshActantBackend` adapts the
ledger to `SwooshCore`'s `SessionStoring` + `ResponseAuditing` protocols.

The previous SpacetimeDB spike (`Backend/SwooshDB` + `SwooshDBClient/
SpacetimeSupervisor.swift`) was retired. ActantDB ships the same
"reducers + audit" properties without an extra runtime dependency
on the spacetime CLI.

## Module map (v0 only)

```
SwooshKit          SDK entry point, re-exports
SwooshCore         AgentKernel actor, agent loop
SwooshConfig       Setup graph, credentials, hardware, permissions, doctor
SwooshScout        Scout sources, redactor, candidate generator
SwooshStorage      SQLite store for memories / setup reports / permissions
SwooshVault        Memory review + approved memory API
SwooshFirewall     Permission model, approval engine, audit log
SwooshTools        Tool protocol, registry, types
SwooshFoundation   Apple Foundation Models adapter
SwooshActantBackend ActantDB adapters (SessionStoring + ResponseAuditing)
SwooshCLI          ArgumentParser commands
SwooshDaemon       swooshd entry point (also supervises actantdb subprocess)
```

## Storage layout

```
~/.swoosh/
├── state.db              SQLite: everything
├── config.json           non-secret config
├── theme.json            UI theme
├── setup-reports/        generated reports
├── logs/                 daemon/agent logs
├── artifacts/            generated files
└── models/               downloaded MLX models
```

Keychain service: `ai.swoosh.agent`

## Scout pipeline

```
Permission gate
  → ScoutSource.scan()
  → SecretRedactor.redact()
  → SwooshStorage.insertScoutRecords()
  → CandidateGenerator.generate()
  → SwooshStorage.insertMemoryCandidates()
  → User review (CLI or app)
  → SwooshStorage.approveMemory() / rejectMemory()
  → AuditLog.append()
```

## Model path (v0)

```
Local summarizer:  Apple Foundation Models (free, on-device)
Remote reasoner:   OpenAI-compatible provider via Keychain API key
```

## CLI commands (v0)

```
swoosh setup quick       full onboarding flow
swoosh doctor            system diagnostics
swoosh scout run         run Scout scan
swoosh scout report      show last scan report
swoosh memory list       list memory candidates
swoosh memory approve    approve pending memories
swoosh memory show       show approved memories
swoosh daemon status     check daemon
```

## Database schema (v0)

```sql
scout_records       (id, source_id, kind, sensitivity, content, metadata, created_at)
memory_candidates   (id, text, category, confidence, sensitivity, status, evidence, created_at)
approved_memories   (id, text, category, sensitivity, source_candidate_id, approved_at)
audit_events        (id, event_type, actor, target, details, created_at)
permissions         (id, permission, level, scope, updated_at)
setup_reports       (id, content, created_at)
```

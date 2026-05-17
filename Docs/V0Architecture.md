# Swoosh v0 Architecture

## Process model

```
Swoosh.app ──┐
swoosh CLI ──┤── SQLite (state.db) ──── Keychain (secrets)
swooshd ─────┘
```

v0 uses **SQLite** as the single state store. All processes share `~/.swoosh/state.db`.

SpacetimeDB is deferred to v0.2 as an optional live state plane.

## Module map (v0 only)

```
SwooshKit        SDK entry point, re-exports
SwooshCore       AgentKernel actor, agent loop
SwooshConfig     Setup graph, credentials, hardware, permissions, doctor
SwooshScout      Scout sources, redactor, candidate generator
SwooshStorage    SQLite state store (sessions, records, memories, audit)
SwooshVault      Memory review + approved memory API
SwooshFirewall   Permission model, approval engine, audit log
SwooshTools      Tool protocol, registry, types
SwooshFoundation Apple Foundation Models adapter
SwooshCLI        ArgumentParser commands
SwooshDaemon     swooshd entry point
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

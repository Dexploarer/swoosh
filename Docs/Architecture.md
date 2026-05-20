# Swoosh Architecture

## Process model

```
Swoosh.app ──┐
swoosh CLI ──┤── Keychain (secrets)
swooshd ─────┴── actantdb serve (subprocess)
                 └─ event ledger / replay / approvals / memories / setup reports
                    at ~/.swoosh/actant.db
```

**All durable state** — sessions, tool calls, response-audit records, memory
candidates, approved memories, setup reports, scout records, permissions —
routes through **ActantDB**, the event-sourced backend with hash-chained
events, replay, and Studio. `swooshd` spawns `actantdb serve --db
~/.swoosh/actant.db --bind 127.0.0.1:<port>` as a child process via
`ActantAgent.ActantDBSupervisor` and exports the listening URL as
`ACTANT_BASE_URL`. `SwooshKit.configure` picks up that env var to build
default loaders/stores/auditors through `SwooshActantBackend`'s conformance
extensions over `ActantAgent.MemoryStore` / `ApprovalCenter` /
`Session<ChatMessage>` / `Auditor<ResponseAuditRecord>`.

The SQLite `SwooshStorage` target and the SpacetimeDB spike were both
retired in favor of this stack.

## Module Map

```
SwooshKit             SDK entry point, re-exports
SwooshCore            AgentKernel actor, agent loop
SwooshConfig          Setup graph, credentials, hardware, permissions, doctor
SwooshScout           Scout sources, redactor, candidate generator
SwooshVault           Memory review + approved memory API
SwooshFirewall        Permission model, approval engine, audit log
SwooshTools           Tool protocol, registry, types
SwooshFoundation      Apple Foundation Models adapter
SwooshActantBackend   ActantAgent ↔ SwooshCore conformance shim (<100 LoC)
SwooshGenerativeUI    Agent-emitted UI (A2UI-shaped: typed UIComponent enum,
                      UISurfaceUpdate wire format, ComponentCatalog gate,
                      UIRenderer SwiftUI walker, sentinel envelope for tools)
SwooshUI              Dashboard, menu bar, toolbar, theme editor, drag-drop,
                      Inspector, Tips, Spatial (RealityView orb / Model3D),
                      Spotlight indexer, FocusFilter, Live Activities,
                      WritingTools + Image Playground hooks, generative
                      surface host
SwooshCLI             ArgumentParser commands
SwooshDaemon          swooshd entry point (also supervises actantdb subprocess)
```

## Storage layout

```
~/.swoosh/
├── actant.db             ActantDB ledger (event-sourced)
├── config.json           non-secret config
├── theme.json            UI theme
├── logs/                 daemon/agent logs (incl. actantdb.log)
├── artifacts/            generated files
└── models/               downloaded MLX models
```

Keychain service: `ai.swoosh.agent`

## Scout pipeline

```
Permission gate
  → ScoutSource.scan()
  → SecretRedactor.redact()
  → ActantClient.saveScoutRecord() (per record)
  → CandidateGenerator.generate()
  → CandidateReviewPlanner.dedupe(existing pending + approved memories)
  → ActantAgent.MemoryStore.propose() (per candidate)
  → ActantClient.saveSetupReport()
  → User review (CLI or app)
  → ActantAgent.MemoryStore.approve() / reject()
```

`swooshd` also runs Scout autopilot in the background. It uses
`ScoutPermissionMode.skipUnavailable`, so it never raises OS permission prompts
while unattended. It reads passive sources such as daemon app-focus signals,
app-usage aggregates, installed/running apps, and any already-granted personal
sources, then proposes only candidates whose normalized text is not already
pending or approved.

## Model Path

```
Local summarizer:  Apple Foundation Models (free, on-device)
Remote reasoner:   OpenAI-compatible provider via Keychain API key
```

## CLI Commands

```
swoosh setup quick       full onboarding flow
swoosh doctor            system diagnostics
swoosh scout run         run Scout scan
swoosh scout report      show last scan report
swoosh memory list       list memory candidates
swoosh memory approve    approve pending memories
swoosh memory show       show approved memories
swoosh daemon status     check daemon
swoosh skills list       list installed/promptable skills
swoosh skills install    install an agentskills-style skill
swoosh cron list         list scheduled jobs
swoosh cron create       create a scheduled agent job
swoosh terminal backends list terminal execution backends
swoosh chat-adapters     list and toggle platform/state adapters
```

## Backend schema

The canonical schema lives in ActantDB (`actantDB/migrations/0001_initial.sql`,
~80 tables). Swoosh consumes the following slice via the `ActantDB` and
`ActantAgent` Swift SDKs:

```
memory               approved memories
memory_candidate     pending/rejected proposals
memory_conflict      detected conflicts
authority_scope      granted permissions
artifact             setup_report rows (kind="setup_report")
context_item         scout_records (source_type="scout")
agent_event          session messages + audit sentinels
tool_call            tool dispatch + approval requests
```

Swoosh never speaks SQL directly; all access goes through `ActantClient` /
`ActantAgent` over HTTP.

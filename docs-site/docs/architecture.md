---
id: architecture
title: Architecture
sidebar_position: 4
---

# Architecture

## Process model

```
Swoosh.app ──┐
swoosh CLI ──┤── Keychain (secrets)
swooshd ─────┴── actantdb serve (subprocess)
                 └─ event ledger / replay / approvals / memories / setup reports
                    at ~/.swoosh/actant.db
```

**All durable state** — sessions, tool calls, response-audit records, memory candidates, approved memories, setup reports, scout records, permissions — routes through **ActantDB**, the event-sourced backend with hash-chained events, replay, and Studio. `swooshd` spawns `actantdb serve` as a child process via `ActantAgent.ActantDBSupervisor` and exports the listening URL as `ACTANT_BASE_URL`. `SwooshKit.configure` picks up that env var to build default stores and auditors.

## Mac + iPhone share one agent

The home Mac is the hub: it runs `swooshd`, which owns the kernel, ActantDB, providers, and tools. The iPhone is a thin HTTP client. There is only ever one `AgentKernel`.

```
                  ┌──────────────────┐
                  │  MacBook / Mac   │
                  │  swooshd (8787)  │
                  │  ActantDB        │
                  │  AgentKernel     │
                  └────────┬─────────┘
                           │  bearer-gated HTTP (LAN)
                  ┌────────┴─────────┐
                  │  iPhone          │
                  │  SwooshiOS       │
                  │  SwooshAPIClient │
                  └──────────────────┘
```

A fully embedded iOS kernel (with CloudKit sync) is in the design phase — see [iOS & Kernel Sync](./ios).

## Dependency hierarchy

```
SwooshKit ──► SwooshCore ──► SwooshTools
   │              ▲              ▲
   ▼              │              │
SwooshActantBackend ──► ActantAgent ──► ActantDB Swift SDK
                                         ▲
                        SwooshFirewall ──┘
                        SwooshFlow / SwooshVault / SwooshToolsets / …
```

## Storage layout

```
~/.swoosh/
├── actant.db           ActantDB ledger (event-sourced, hash-chained)
├── config.json         Non-secret runtime config
├── api_token           Daemon bearer token (mode 0600)
├── theme.json          UI theme
├── logs/               Daemon + ActantDB logs
├── artifacts/          Generated files and media
└── models/             Downloaded MLX models
```

**Keychain services:**

- `ai.swoosh.agent` — setup/runtime credentials managed by `SwooshConfig`.
- `ai.swoosh.secrets` — provider secrets managed by `SwooshSecrets.KeychainSecretStore`.

## Security token flow

`swooshd` resolves a bearer token at startup in this order:

1. `SWOOSH_API_TOKEN` environment variable
2. `~/.swoosh/api_token` (auto-persisted on first mint)
3. Freshly minted via `SecRandomCopyBytes`

The token is printed in the startup log and required on every `/api/*` request via `BearerAuthMiddleware` (constant-time compare). When the token cannot be resolved, the entire `/api/*` tree is shadow-mounted under `DenyAllMiddleware`.

## Model routing

```
Local summarizer:   Apple Foundation Models (free, on-device)
Remote reasoner:    OpenAI-compatible provider via Keychain API key
```

`SwooshProviders` holds remote adapters: `OpenAIResponsesProvider`, `OpenRouterProvider`, `LocalOpenAICompatibleProvider`, `ElizaCloudProvider`, routed by `ProviderRouter`. `SwooshMLX` is the local Apple-silicon path. `SwooshFoundation` is the Apple Foundation Models adapter.

## Scout pipeline

```
Permission gate
  → ScoutSource.scan()
  → SecretRedactor.redact()
  → ActantClient.saveScoutRecord()    (per record)
  → CandidateGenerator.generate()
  → CandidateReviewPlanner.dedupe()   (against pending + approved memories)
  → ActantAgent.MemoryStore.propose() (per candidate)
  → ActantClient.saveSetupReport()
  → User review (CLI or app)
  → ActantAgent.MemoryStore.approve() / reject()
```

`swooshd` also runs Scout autopilot in the background with `ScoutPermissionMode.skipUnavailable`, so it never raises OS permission prompts while unattended.

## Backend schema (ActantDB slice)

Swoosh never speaks SQL directly — all access goes through `ActantClient` / `ActantAgent` over HTTP.

| Table | Used for |
|-------|----------|
| `memory` | Approved memories |
| `memory_candidate` | Pending / rejected proposals |
| `memory_conflict` | Detected conflicts |
| `authority_scope` | Granted permissions |
| `artifact` | Setup report rows (`kind="setup_report"`) |
| `context_item` | Scout records (`source_type="scout"`) |
| `agent_event` | Session messages + audit sentinels |
| `tool_call` | Tool dispatch + approval requests |

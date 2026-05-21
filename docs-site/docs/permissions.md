---
id: permissions
title: Permissions & Security
sidebar_position: 7
---

# Permissions & Security

Swoosh has two independent permission controls that work together:

- **`PermissionProfilePreset`** — decides which `SwooshPermission` cases the firewall grants.
- **`ToolCallPolicy`** and **`SwooshSafetyConfig`** — decide whether the model may call tools, whether approvals are required, and whether advanced capabilities are unlocked.

## Permission profiles

| Profile | Firewall grants | Tool policy | Safety flags |
|---------|-----------------|-------------|--------------|
| `safe` | Read-only runtime, memory, audit, and network status | Restrictive, low chain depth | Locked |
| `developer` | File, Git, Swift/Xcode, memory, workflow, skills, and provider access | Default agent policy | Locked |
| `automation` | Developer plus calendar, reminders, scheduling, app usage, focus signals | Default agent policy | Locked |
| `power` | Nearly all permissions except mainnet writes | Critical model calls allowed, approvals still required | Development safety |
| `autonomous` | Every `SwooshPermission` case | Full model tool access, high limits, approvals optional | All safety flags enabled |
| `custom` | Developer defaults until edited | Default agent policy | Locked |

:::note autonomous is intentional
`autonomous` is the explicit opt-in for unattended agents that can run without human approval. Safe modes remain available and are the default unless the user chooses otherwise.
:::

Set during setup:

```bash
swift run swoosh setup quick --permissions developer
```

Check at any time:

```bash
swift run swoosh permissions --status
```

## Tool call policy

`ToolCallPolicy` is enforced by the agent loop and registry:

| Field | Effect |
|-------|--------|
| `maxToolCallsPerTurn` | Total tool calls allowed in one turn |
| `maxToolChainDepth` | Maximum chained model tool-call depth |
| `allowModelToolCalls` | If `false`, the model receives no tool descriptors and returned tool calls are blocked |
| `allowHumanOnlyFromModel` | If `false`, `humanOnly` tools are hidden from and blocked for model-origin calls |
| `allowCriticalToolsFromModel` | If `false`, critical-risk tools are hidden from and blocked for model-origin calls |
| `requireApprovalForMediumRiskAndAbove` | If `true`, model-origin medium/high/critical calls require approval even when the tool itself says `never` |

## Safety config

`SwooshSafetyConfig` gates advanced capabilities that are off by default:

| Flag | Capability |
|------|------------|
| `autonomousTradingEnabled` | Autonomous trading workflows |
| `swapExecutionEnabled` | DEX swap execution |
| `portfolioRecommendationsEnabled` | Portfolio recommendation tools |
| `privateKeyCustodyEnabled` | Private-key custody in Keychain |
| `seedPhraseIngestionEnabled` | Seed phrase ingestion |
| `cookieIngestionEnabled` | Browser cookie ingestion |
| `shellToBlockchainBridgeEnabled` | Shell-to-wallet escalation path |
| `modelSelfApprovalEnabled` | Model-origin calls can bypass approval prompts |
| `mainnetWritesByDefault` | Mainnet write permissions granted by default |

## Approval semantics

| Approval type | Behaviour |
|---------------|-----------|
| `askFirstTime` | Can be approved for the session; subsequent calls in the same session proceed without re-asking |
| `askEveryTime` | Always creates a new approval request, even after a session approval |
| `humanOnly` | Blocks model-origin calls unless both the runtime tool policy and safety config explicitly opt into autonomous behaviour |

Every tool call still passes through `SwooshFirewallActor`, is audited, and records approval state when approval is required.

## The Firewall

`SwooshFirewall` is the **only** permission enforcement point. Key invariants:

- `SwooshFirewallActor` denies any permission not explicitly granted — no implicit allow.
- Tools must not bypass it; there is no escape hatch.
- `SwooshAuditLog` is the in-memory audit implementation; all events are also persisted to ActantDB.

## Tool risk levels

Tools declare one of four risk levels:

| Level | Meaning |
|-------|---------|
| `low` | Read-only, no side effects |
| `medium` | Writes or mutations that are reversible |
| `high` | Irreversible writes, network calls with side effects |
| `critical` | Financial transactions, mainnet writes, destructive operations |

## Surfaces

- **Setup:** `swoosh setup quick --permissions <profile>`
- **CLI status:** `swoosh permissions --status` — prints the active profile, tool policy, and key safety flags
- **REPL:** `/permissions`, `/firewall`
- **macOS dashboard:** Settings shows runtime config, every `ToolCallPolicy` field, and every `SwooshSafetyConfig` flag
- **iOS companion:** Settings reads `/api/runtime/config` and shows the paired Mac daemon profile, tool policy, and safety flags

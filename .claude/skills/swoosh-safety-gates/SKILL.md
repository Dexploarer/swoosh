---
name: swoosh-safety-gates
description: The 8 engineering rules that gate any change touching prompts, tools, permissions, audit, secrets, or crypto. Use when touching PromptBuilder, SwooshFirewall, SwooshTools, SwooshToolsets, SwooshScout, SwooshSecrets, AgentToolLoop, or any /api/* route. Encodes the privacy boundary, the humanOnly invariant, and the crypto-input ban.
---

# Swoosh safety gates — per-area checklists

The 8 engineering rules live in the root `CLAUDE.md` (and `README.md`) — don't re-derive them. This skill is the **runnable checklist** form, broken out by which sensitive area you're touching. Use it as a pre-commit pass.

## When this skill matters

The trigger paths — touch any of these, run this checklist:

- `Sources/SwooshCore/PromptBuilder.swift` — the privacy boundary
- `Sources/SwooshCore/AgentKernel.swift`, `AgentToolLoop.swift` — the run-loop
- `Sources/SwooshFirewall/**` — the only enforcement point
- `Sources/SwooshTools/SwooshPermission.swift` — the permission enum
- `Sources/SwooshToolsets/**` — concrete tools
- `Sources/SwooshScout/**` — the personalization scanner
- `Sources/SwooshSecrets/**` — the secret scavenger
- `Sources/SwooshAPI/**` — the daemon HTTP surface

## Concrete checks per area

### PromptBuilder / AgentKernel

- [ ] Does any new context source funnel through `buildSystemPrompt`?
- [ ] Are `ResponseAuditRecord` exclusion flags set correctly for new memory categories?
- [ ] Does the new code log via `AuditLogging` (not `print`, not OSLog)?

### SwooshFirewall

- [ ] Every new tool's dispatch path calls `firewall.require(permission)`?
- [ ] No `firewall.require` bypass — even debug paths?
- [ ] New permission cases added to `SwooshPermission` and documented in `Docs/PermissionModel.md`?

### Crypto toolsets

- [ ] `Input` types contain no private-key / seed-phrase / cookie / session-token field?
- [ ] Signing happens via the existing wallet/device path, not via tool-provided keys?
- [ ] Funds-moving tools are `approval = .humanOnly`?

### Scout

- [ ] Secret redactor runs **before** ActantDB write?
- [ ] New source has `Sensitivity` set (`.high` for personal data)?
- [ ] `PersonalizationDepth` gates the source correctly?
- [ ] Source's permission case exists and `ScoutSource.checkPermission` returns the right state?

### `/api/*` routes

- [ ] Route requires `BearerAuthMiddleware`?
- [ ] Tokenless startup mounts `DenyAllMiddleware` (don't bypass even for "dev")?
- [ ] Constant-time compare on token? (Don't introduce string equality.)
- [ ] New wire types live in `Sources/SwooshClient/WireTypes.swift`?

## What to do when a gate trips

Don't push through a gate failure. Each rule corresponds to a past incident or a load-bearing invariant. If a gate seems to block a legitimate change, the right move is to **adjust the gate explicitly** (with a doc + audit) rather than bypass it locally.

## Related bundled runtime skill

`Skills/Bundled/swoosh-safety-review.md` is Swoosh's own runtime skill for the agent to use when reviewing its own changes. This file is the equivalent for me (Claude Code) when editing this repo. Keep them in sync if either is updated.

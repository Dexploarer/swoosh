# Project Learnings

> Managed by `/learn`. Append-only — latest entry wins on conflicts.
> Loaded into every session via `.claude/hooks/learnings-context.sh` (SessionStart).

## Patterns

### typed-tool-contract
- **Insight:** Every SwooshTool ships typed `Input`/`Output` (`Codable & Sendable`) and is wrapped via `TypeErasedTool<T>` for registry storage. Don't add a tool that accepts loose `[String: Any]` or returns raw JSON.
- **Confidence:** 10/10
- **Source:** manual
- **Files:** Sources/SwooshTools/Tool.swift
- **Date:** 2026-05-22

### firewall-is-sole-permission-gate
- **Insight:** `SwooshFirewallActor.require(...)` is the ONLY enforcement point. Tools must not check permissions inline or bypass the firewall — anything that does is a safety regression.
- **Confidence:** 10/10
- **Source:** manual
- **Files:** Sources/SwooshFirewall/, Sources/SwooshTools/SwooshPermission.swift
- **Date:** 2026-05-22

### prompt-builder-privacy-boundary
- **Insight:** `PromptBuilder.buildSystemPrompt` admits only approved memories + setup-report summary + permission summary. Rejected memory candidates, raw Scout records, cookies, secrets, SSH keys, and browser history NEVER enter prompts — hard rule, enforced by exclusion flags on `ResponseAuditRecord`.
- **Confidence:** 10/10
- **Source:** manual
- **Files:** Sources/SwooshCore/PromptBuilder.swift, Sources/SwooshCore/ResponseAuditRecord.swift
- **Date:** 2026-05-22

### ios-app-imports-swooshclient-only
- **Insight:** `Apps/SwooshiOS` imports ONLY `SwooshClient` — never `SwooshKit`. SwooshKit pulls in `ActantDBSupervisor` which uses `Foundation.Process` and breaks iOS builds. The wire format lives in `SwooshClient/WireTypes.swift`.
- **Confidence:** 10/10
- **Source:** manual
- **Files:** Apps/SwooshiOS/, Sources/SwooshClient/WireTypes.swift
- **Date:** 2026-05-22

## Pitfalls

### swift-test-must-be-single-sync-bash
- **Insight:** `swift test` must be a single sync Bash call with timeout 600000ms. NEVER run via Monitor, NEVER tee+tail, NEVER spawn two concurrent SwiftPM invocations — all three stall the harness for 10+ minutes. ~1749 tests, ~14s wall clock. **Pre-flight is mandatory:** before invoking, `pgrep -fl "swift test|swift build|swift-test|swift-build|swiftpm-testing-helper|SwooshPackage|xctest"` must be empty. Killing the parent Bash task does NOT kill swift-test/helper children — they orphan and keep SwiftPM's `.build/` lock, making the next `swift test` idle silently. If pgrep prints anything you own, `pgrep -f "swift-test|swiftpm-testing-helper|SwooshPackage" | xargs -r kill -9` and re-pgrep until clean. If it belongs to another session, wait.
- **Confidence:** 10/10
- **Source:** manual
- **Files:**
- **Date:** 2026-05-23

### socraticode-swift-graph-broken
- **Insight:** SocratiCode's file-graph and `codebase_impact` tools are broken for Swift — they miss imports and return empty/wrong results. Semantic search (`codebase_search`/`_symbol`) works well. For refactor blast-radius use `grep`, not graph queries.
- **Confidence:** 9/10
- **Source:** manual
- **Files:**
- **Date:** 2026-05-22

### never-edit-xcodeproj-directly
- **Insight:** `Swoosh.xcodeproj` is generated from `project.yml` via XcodeGen. Edit `project.yml`, then run `xcodegen generate`. Direct .xcodeproj edits get wiped on regen and won't survive a fresh checkout.
- **Confidence:** 10/10
- **Source:** manual
- **Files:** project.yml, Swoosh.xcodeproj/
- **Date:** 2026-05-22

## Preferences

### agent-persona-detour
- **Insight:** User-facing agent name is "Detour". "Swoosh" is product/codebase terminology only — never surface it in system prompts, chat headers, drawers, or About rows shown to users.
- **Confidence:** 10/10
- **Source:** manual
- **Files:**
- **Date:** 2026-05-22

### loc-ceiling-400
- **Insight:** Hard ceiling of 400 LOC per source file. `.claude/hooks/loc-guard.sh` warns at 350 and blocks at >400. If a file is approaching 350, split before adding more.
- **Confidence:** 10/10
- **Source:** manual
- **Files:** .claude/hooks/loc-guard.sh
- **Date:** 2026-05-22

### file-header-purpose-and-version
- **Insight:** Every source file carries a one-line purpose comment + a version tag (e.g. `0.4A`, `0.4B`). Keep this style when adding new files in an existing module; bump the suffix when materially revising a file's contract.
- **Confidence:** 8/10
- **Source:** manual
- **Files:**
- **Date:** 2026-05-22

## Architecture

### actantdb-is-the-state-spine
- **Insight:** All durable agent state (sessions, memories, approvals, audit records) goes through ActantDB at `~/.swoosh/actant.db`, fronted by `actantdb serve` spawned by `swooshd` via `ActantAgent.ActantDBSupervisor`. Earlier SQLite `SwooshStorage` target and SpacetimeDB spike were both retired. `SwooshVault` and `SwooshFirewall` still use `SQLite.swift` directly for caches that don't belong on the event ledger — that's why the SQLite dep stays.
- **Confidence:** 10/10
- **Source:** manual
- **Files:** Sources/SwooshActantBackend/, /Users/home/actantDB/sdks/swift/
- **Date:** 2026-05-22

### one-kernel-mac-is-hub
- **Insight:** Mac and iPhone share a SINGLE `AgentKernel`. The Mac runs `swooshd` (owns kernel + ActantDB + providers + tools); the iPhone is a thin HTTP client. Never instantiate a second kernel on iOS — pair via bearer token and `SwooshAPIClient`.
- **Confidence:** 10/10
- **Source:** manual
- **Files:** Sources/SwooshDaemon/, Sources/SwooshClient/, Apps/SwooshiOS/
- **Date:** 2026-05-22

### daemon-bearer-token-resolution
- **Insight:** `swooshd` resolves its bearer token in this order: `SWOOSH_API_TOKEN` env → `~/.swoosh/api_token` (auto-persisted) → freshly minted via `SecRandomCopyBytes`. If token resolution fails, the entire `/api/*` tree is shadow-mounted under `DenyAllMiddleware` so an accidentally-public daemon still refuses to act. Bind address defaults to `127.0.0.1`; `SWOOSH_HOST=0.0.0.0` opts into LAN.
- **Confidence:** 10/10
- **Source:** manual
- **Files:** Sources/SwooshDaemon/, Sources/SwooshAPI/
- **Date:** 2026-05-22

## Tools

### socraticode-via-plugin-prefix
- **Insight:** This repo is indexed by SocratiCode under the plugin prefix `mcp__plugin_socraticode_socraticode__*`. If a standalone `mcp__socraticode__*` ever appears alongside, the user has a duplicate install — `claude mcp remove socraticode` to fix.
- **Confidence:** 9/10
- **Source:** manual
- **Files:**
- **Date:** 2026-05-22

### context-artifacts-unconfigured
- **Insight:** SocratiCode context artifacts for `Docs/` are not yet configured. Semantic search works on source but won't surface architecture notes from `Docs/Architecture.md`, `Docs/iOS-Kernel-and-Sync.md`, etc. — read those files directly when answering architecture questions.
- **Confidence:** 8/10
- **Source:** manual
- **Files:** Docs/
- **Date:** 2026-05-22

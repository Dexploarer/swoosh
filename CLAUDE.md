# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

**Swoosh** is a Swift-native, MLX-capable, Apple-first autonomous agent runtime — an embeddable SDK (`SwooshKit`), a local daemon (`swooshd`), a CLI (`swoosh`), and a native macOS menu-bar app. Targets **macOS 26 / iOS 26**, Swift **6.3**. The whole codebase is `Sendable`-clean and structured around Swift actors.

## Build, test, run

```bash
swift build                              # build everything
swift build -c release
swift test                               # run all test targets
swift test --filter SwooshFlowTests      # run one target
swift test --filter SwooshFlowTests.WorkflowReplayTests/testReplayDeterminism  # one test
swift run swoosh <subcommand>            # CLI (subcommands: setup, ask, doctor, scout, memory, model, daemon, chat, self-test, permissions, provider)
swift run swooshd                        # local daemon

xcodegen generate                        # regenerate Swoosh.xcodeproj from project.yml
```

The Xcode project (`Swoosh.xcodeproj`) is **generated** from `project.yml` via [XcodeGen]; do not edit `.xcodeproj` files directly. It wraps the SwiftPM package for the menu-bar app target + widget extension only — library/CLI/daemon work happens via `swift build`.

**Backend strategy:** `SwooshStorage` (SQLite at `~/.swoosh/state.db`) holds memories, setup reports, and permissions. **Session messages + response audit records** go through **ActantDB** — the event-sourced sibling repo at `/Users/home/actantDB/` — consumed via its Swift SDK (`sdks/swift/`) and adapted to `SwooshCore` protocols in the `SwooshActantBackend` module. `swooshd` is expected to spawn `actantdb serve` as a child process at startup. The earlier SpacetimeDB spike (`Backend/SwooshDB`, `SpacetimeSupervisor.swift`) was retired in favor of ActantDB.

## Architecture

The package is sliced into ~45 single-purpose modules in `Sources/`. The dependency hierarchy is roughly:

```
SwooshKit  ──►  SwooshCore  ──►  SwooshTools  ──►  SwooshStorage
                    ▲                ▲
   SwooshFirewall ──┘                │  (every tool subsystem depends on SwooshTools)
   SwooshFlow / SwooshBoard / SwooshVault / SwooshToolsets / etc.
```

- **`SwooshKit`** is the public SDK; it `@_exported import`s `SwooshCore` and exposes the `Swoosh.configure { ... }` entry point.
- **`SwooshCore/AgentKernel`** is an `actor`. `run(AgentRequest)` does: load approved context → build system prompt → call `ModelProvider` → append to session store → write `ResponseAuditRecord`. `AgentToolLoop.swift` adds the tool-calling variant.
- **`SwooshCore/PromptBuilder`** is the **privacy boundary**. Only approved memories + setup-report summary + permission summary enter prompts. Rejected memory candidates, raw Scout records, cookies, secrets, SSH keys, browser history — **never**.
- **`SwooshTools/Tool.swift`** defines `SwooshTool` (typed `Input`/`Output`, static `name`/`permission`/`risk`/`approval`/`toolset`). Tools are wrapped with `TypeErasedTool<T>` for registry storage. `ToolsetID` enumerates the toolset families (core, memory, scout, files, git, swiftDev, evm, solana, hyperliquid, uniswap, mcp, …).
- **`SwooshFirewall`** is the **only** permission enforcement point. `SwooshFirewallActor` denies any permission not explicitly granted. Tools must not bypass it. `SwooshAuditLog` is the in-memory `AuditLogging` impl.
- **`SwooshToolsets`** contains the concrete tool implementations (`CoreTools`, `FileTools`, `GitTools`, `JupiterSwapTools`, `HyperliquidTradeTools`, etc.) registered through `DefaultToolRegistrar.registerAll(into:dependencies:)`. Crypto toolsets pull in `JupSwift`, `HyperliquidSwift`, `BigInt`.
- **`SwooshFlow`** is the workflow engine: `WorkflowExecutionEngine`, `WorkflowDryRunEngine`, `WorkflowReplayEngine`, `WorkflowTrigger*` — every workflow is replayable, dry-runnable, and trigger-dispatched.
- **`SwooshProviders`** holds remote model adapters: `OpenAIResponsesProvider`, `OpenRouterProvider`, `LocalOpenAICompatibleProvider`, `ElizaCloudProvider`, routed by `ProviderRouter`.
- **`SwooshMLX`** is the local Apple-silicon path (MLXLLM, MLXVLM). **`SwooshFoundation`** is the Apple Foundation Models adapter. **`SwooshModels`** is the standalone model catalog + HF discovery.
- **`SwooshScout`** is the personalization scanner: source scan → secret redactor → SQLite insert → candidate generator → user review → approved memory. See `Docs/V0Architecture.md` for the full pipeline.
- **`SwooshUI`** is shared SwiftUI for both `App/SwooshApp.swift` (menu-bar app via `MenuBarExtra`) and the iOS app. **`SwooshWidgets`** provides the widget extension hosted from `WidgetExtension/`.
- **`SwooshMacros` / `SwooshMacroPlugin`** is the compile-time `@SwooshTool` macro infrastructure (swift-syntax 600).
- **`SwooshActantBackend`** adapts the ActantDB SDK to `SwooshCore`'s `SessionStoring` + `ResponseAuditing` protocols. Three files: `ActantBackendConfig` (shared client + `waitForReady` probe), `ActantSessionStore`, `ActantResponseAuditor`. Audit records ride the same ledger as messages — `append_agent_message` with a JSON sentinel `{"_swoosh_audit": true, ...}` — so Studio + replay see them natively.

The CLI (`Sources/SwooshCLI`) uses `swift-argument-parser`; entry point is `SwooshCommand.swift` with subcommands split across `SetupCommands.swift`, `ChatAskCommands.swift`, `ScoutMemoryCommands.swift`, `ProviderCommands.swift`. Default subcommand is `chat`.

## Storage & secrets

- All processes share `~/.swoosh/state.db` (SQLite via `SQLite.swift`). Schema sketch in `Docs/V0Architecture.md`.
- Secrets live in Keychain under service `ai.swoosh.agent`. `SwooshSecrets` provides scavengers (Environment / ConfigFile / Keychain) — read order matters; `KeychainSecretStore` is the canonical store.
- Other state lives under `~/.swoosh/{config.json, theme.json, setup-reports/, logs/, artifacts/, models/}`.
- macOS sandbox is **disabled** for both the app and widget extension (see `project.yml` — `ENABLE_APP_SANDBOX: false`, and `App/Swoosh.entitlements`). App group: `group.ai.swoosh.shared`.

## Engineering rules (from `README.md`, enforced throughout the code)

1. Every tool is typed (`SwooshTool` with `Codable & Sendable` I/O).
2. Every risky action is permissioned (via `SwooshFirewallActor.require`).
3. Every agent step is logged (`AuditEntry` through `AuditLogging`).
4. Every workflow is replayable (`SwooshFlow` records traces).
5. Every memory is inspectable (`/why` reads `ResponseAuditRecord`).
6. Rejected memory candidates / raw Scout records / cookies / secrets **never** enter prompts — this is a hard rule in `PromptBuilder.buildSystemPrompt` and `ResponseAuditRecord`'s exclusion flags.
7. Crypto tools must not accept private keys, seed phrases, or cookies as input (see `AgentToolLoop.swift` header).
8. `humanOnly` tools cannot be executed by model-origin calls; the model cannot approve its own tool calls.

## Conventions

- Concurrency: actors for stateful subsystems (`AgentKernel`, `SwooshFirewallActor`, `SwooshAuditLog`, `ToolRegistry`). Everything crossing actor boundaries is `Sendable`.
- File headers carry a one-line purpose + the 0.4A/0.4B/etc. version tag — keep this style when adding new files in an existing module.
- `SwooshPermission` is a string-raw enum; add new permission cases in `SwooshTools/SwooshPermission.swift` and update `Docs/PermissionModel.md`.
- When adding a new toolset family, also add its case to `ToolsetID` and a `register<Name>` hook in `SwooshToolsets/Exports.swift` (the registrar).
- Apps live in three places: `App/` (menu-bar macOS target wired through XcodeGen), `Apps/SwooshMac` / `Apps/SwooshiOS` (SwiftPM-built apps), `Apps/SwooshDashboard` (currently empty scaffold).

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

**Backend strategy:** all durable state — memories, setup reports, permissions, session messages, response audit records — goes through **ActantDB** (the event-sourced sibling repo at `/Users/home/actantDB/`). Swoosh consumes ActantDB via two layers: the low-level `ActantDB` Swift SDK and the opinionated `ActantAgent` facade (both at `actantDB/sdks/swift/`). `SwooshActantBackend` is a thin conformance shim (<100 LoC) that lets `ActantAgent.MemoryStore` / `Session<ChatMessage>` / `Auditor<ResponseAuditRecord>` / `ApprovalCenter` satisfy `SwooshCore`'s five protocols directly. `swooshd` spawns `actantdb serve` as a child via `ActantAgent.ActantDBSupervisor` at startup and exports the listening URL as `ACTANT_BASE_URL`; `SwooshKit.configure` picks up that env var to build the default kernel context. The earlier SQLite `SwooshStorage` target and the SpacetimeDB spike were both retired in favor of this stack.

## Architecture

The package is sliced into ~45 single-purpose modules in `Sources/`. The dependency hierarchy is roughly:

```
SwooshKit ──► SwooshCore ──► SwooshTools
   │              ▲              ▲
   ▼              │              │  (every tool subsystem depends on SwooshTools)
SwooshActantBackend  ──►  ActantAgent  ──►  ActantDB  (Swift SDK; spawns actantdb subprocess)
                                              ▲
                          SwooshFirewall ─────┘
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
- **`SwooshScout`** is the personalization scanner: source scan → secret redactor → ActantDB `saveScoutRecord` → candidate generator → `MemoryStore.propose` → user review → `MemoryStore.approve` / `reject`. See `Docs/V0Architecture.md` for the full pipeline.
- **`SwooshUI`** is shared SwiftUI for both `App/SwooshApp.swift` (menu-bar app via `MenuBarExtra`) and the iOS app. Subfolders: `MenuBar/` (popover + customizer), `Toolbar/` (window toolbar), `ContextMenus/`, `Themes/` (live theme editor, mesh gradients, symbol effects, choreography), `Tips/` (TipKit onboarding), `Interactions/` (drag-drop transferables, scroll/hover, native EditCommands), `Inspector/` (side-panel detail), `Spatial/` (RealityView agent orb + `Model3D` hero), `Spotlight/` (`CoreSpotlight` indexer), `Focus/` (`SetFocusFilterIntent`), `LiveActivities/` (`ActivityKit` Dynamic Island), `AppleIntelligence/` (`WritingTools` composer + Image Playground), `GenerativeSurfaces/` (host bridge for `SwooshGenerativeUI`). **`SwooshWidgets`** provides the widget extension hosted from `WidgetExtension/`.
- **`SwooshGenerativeUI`** is the agent-to-UI layer modeled after Google's A2UI: typed `UIComponent` enum, flat `UISurfaceUpdate` wire format addressed by string IDs, `ComponentCatalog` security gate (only registered types render), a SwiftUI `UIRenderer` that walks the tree, and a sentinel envelope (`_swoosh_ui` JSON key) so tools can return UI inside their normal `JSONValue` output. The host's `GenerativeSurfaceHost` (in `SwooshUI/GenerativeSurfaces/`) accepts surfaces and routes `UIAction`s back to tool calls, approvals, and surface switches.
- **`SwooshMacros` / `SwooshMacroPlugin`** is the compile-time `@SwooshTool` macro infrastructure (swift-syntax 600).
- **`SwooshActantBackend`** is a single-file conformance shim that lets `ActantAgent.MemoryStore`, `ActantAgent.ApprovalCenter`, and per-call adapters over `ActantAgent.Session<ChatMessage>` + `ActantAgent.Auditor<ResponseAuditRecord>` satisfy `SwooshCore`'s five protocols. The shape is "one-line extensions, no adapter classes" — under 100 LoC for the whole module. Audit records ride the same ledger as messages via the auditor's JSON sentinel envelope so Studio + replay see them natively.

The CLI (`Sources/SwooshCLI`) uses `swift-argument-parser`; entry point is `SwooshCommand.swift` with subcommands split across `SetupCommands.swift`, `ChatAskCommands.swift`, `ScoutMemoryCommands.swift`, `ProviderCommands.swift`. Default subcommand is `chat`.

## Storage & secrets

- All durable agent state — sessions, memories, approvals, audit records — lives in **ActantDB** at `~/.swoosh/actant.db`, fronted by `actantdb serve` (spawned by `swooshd` via `ActantAgent.ActantDBSupervisor`). Schema sketch in `Docs/V0Architecture.md`.
- A handful of subsystems (`SwooshVault`, `SwooshFirewall`, `SwooshBoard`) still use `SQLite.swift` directly for local caches that don't belong on the event ledger; that's why the `SQLite.swift` package dependency stays.
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

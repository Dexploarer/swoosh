Update the reference to match an existing section heading.

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
xcodebuild -project Swoosh.xcodeproj -scheme Swoosh -destination 'platform=macOS' build   # menu-bar app
xcodebuild -project Swoosh.xcodeproj -scheme SwooshWidgetExtension build                  # widget extension
xcodebuild -project Swoosh.xcodeproj -scheme SwooshiOS \
  -destination 'generic/platform=iOS Simulator' build                                      # iOS app (sim build)
xcodebuild -project Swoosh.xcodeproj -scheme SwooshiOS \
  -destination 'generic/platform=iOS' build                                                # iOS app (device build, signs with team GY5597YK9P)
```

The Xcode project (`Swoosh.xcodeproj`) is **generated** from `project.yml` via [XcodeGen]; do not edit `.xcodeproj` files directly. It wraps the SwiftPM package for the menu-bar app, widget extension, and iOS companion app — library/CLI/daemon work happens via `swift build`. After changing `project.yml`, run `xcodegen generate` before building in Xcode. `DEVELOPMENT_TEAM` is set to `GY5597YK9P` (Apple Developer team for the project) in `project.yml`, so `SwooshiOS` signs automatically for both simulator and on-device installs; the matching team provisioning profile for `ai.swoosh.app.ios` is already in `~/Library/Developer/Xcode/UserData/Provisioning Profiles/`.

**Backend strategy:** all durable state — memories, setup reports, permissions, session messages, response audit records — goes through **ActantDB** (the event-sourced sibling repo at `/Users/home/actantDB/`). Swoosh consumes ActantDB via two layers: the low-level `ActantDB` Swift SDK and the opinionated `ActantAgent` facade (both at `actantDB/sdks/swift/`). `SwooshActantBackend` is a thin conformance shim (<100 LoC) that lets `ActantAgent.MemoryStore` / `Session<ChatMessage>` / `Auditor<ResponseAuditRecord>` / `ApprovalCenter` satisfy `SwooshCore`'s five protocols directly. `swooshd` spawns `actantdb serve` as a child via `ActantAgent.ActantDBSupervisor` at startup and exports the listening URL as `ACTANT_BASE_URL`; `SwooshKit.configure` picks up that env var to build the default kernel context. The earlier SQLite `SwooshStorage` target and the SpacetimeDB spike were both retired in favor of this stack.

**Mac + iPhone share one agent.** The home Mac is the hub: it runs `swooshd`, which owns the kernel, ActantDB, providers, and tools. The iPhone is a thin HTTP client. There is only ever one `AgentKernel`. Wire details:

- `swooshd` resolves a bearer token at startup in the order `SWOOSH_API_TOKEN` env → `~/.swoosh/api_token` (auto-persisted) → freshly minted via `SecRandomCopyBytes`. The token is printed in the startup log and required on every `/api/*` request via `BearerAuthMiddleware` (constant-time compare). When the token cannot be resolved, the entire `/api/*` tree is shadow-mounted under `DenyAllMiddleware` so an accidentally-public daemon still refuses to act.
- Bind address is `127.0.0.1` by default (`SWOOSH_HOST=0.0.0.0` to opt into LAN exposure). The token is required in either mode — the loopback default is defense in depth, not the only line of defense.
Add an exception path (e.g., 'unless the user explicitly requests it') or escalation ('ask the user for confirmation').
- **`Apps/SwooshiOS/`** is a real SwiftUI app (`SwooshiOSApp` → `RootView` → tabbed `ChatView`/`SettingsView`) targeting iOS 26. Settings is the pairing form (host URL + bearer token paste). Chat posts to `/api/agent/chat` via `SwooshAPIClient`. The Info.plist carries `NSLocalNetworkUsageDescription` + `NSBonjourServices=_swoosh._tcp` so local-network access is granted on iOS 14+ and Bonjour discovery is a near-term, not-blocked addition.
Split into multiple lines. Config files should read like command lists, not paragraphs.

## Architecture

The package is sliced into ~47 single-purpose modules in `Sources/` (mirrored by ~23 test targets in `Tests/`). The dependency hierarchy is roughly:

```
SwooshKit ──► SwooshCore ──► SwooshTools
   │              ▲              ▲
   ▼              │              │  (every tool subsystem depends on SwooshTools)
SwooshActantBackend  ──►  ActantAgent  ──►  ActantDB  (Swift SDK; spawns actantdb subprocess)
                                              ▲
                          SwooshFirewall ─────┘
List all items explicitly â 'etc' leaves AI guessing
```

- **`SwooshKit`** is the public SDK; it `@_exported import`s `SwooshCore` and exposes the `Swoosh.configure { ... }` entry point. **macOS/Linux only** — pulls in `SwooshActantBackend` → `ActantAgent.ActantDBSupervisor` which spawns child processes.
- **`SwooshClient`** is the cross-platform client SDK (iOS + macOS). Defines the JSON wire format the daemon speaks (`ChatRequest`/`ChatResponse` etc.), a `URLSession`-backed `SwooshAPIClient` actor, and `TokenStore`/`HostStore`. No internal deps — safe to import from any platform.
- **`SwooshCore/AgentKernel`** is an `actor`. `run(AgentRequest)` does: load approved context → build system prompt → call `ModelProvider` → append to session store → write `ResponseAuditRecord`. `AgentToolLoop.swift` adds the tool-calling variant.
- **`SwooshCore/PromptBuilder`** is the **privacy boundary**. Only approved memories + setup-report summary + permission summary enter prompts. Rejected memory candidates, raw Scout records, cookies, secrets, SSH keys, browser history — **never**.
- **`SwooshTools/Tool.swift`** defines `SwooshTool` (typed `Input`/`Output`, static `name`/`permission`/`risk`/`approval`/`toolset`). Tools are wrapped with `TypeErasedTool<T>` for registry storage. `ToolsetID` enumerates the toolset families (core, memory, scout, files, git, swiftDev, evm, solana, hyperliquid, uniswap, mcp, …).
Add an exception path (e.g., 'unless the user explicitly requests it') or escalation ('ask the user for confirmation').
List all items explicitly â 'etc' leaves AI guessing
- **`SwooshFlow`** is the workflow engine: `WorkflowExecutionEngine`, `WorkflowDryRunEngine`, `WorkflowReplayEngine`, `WorkflowTrigger*` — every workflow is replayable, dry-runnable, and trigger-dispatched.
- **`SwooshProviders`** holds remote model adapters: `OpenAIResponsesProvider`, `OpenRouterProvider`, `LocalOpenAICompatibleProvider`, `ElizaCloudProvider`, routed by `ProviderRouter`.
Write it as "**HF (Full Name Here)**" on first mention.
- **`SwooshScout`** is the personalization scanner: source scan → secret redactor → ActantDB `saveScoutRecord` → candidate generator → `MemoryStore.propose` → user review → `MemoryStore.approve` / `reject`. See `Docs/Architecture.md` for the full pipeline. The deep-personalization sources live in `Sources/SwooshScout/PersonalSources.swift` and `AppUsageRecorder.swift`: `AppUsageSource` (Mac equivalent of iOS Screen Time — daemon-side `NSWorkspace` observer writes app-focus events to `~/.swoosh/app-usage.jsonl`, source aggregates per-app totals over a configurable window); `CalendarSource` and `RemindersSource` (EventKit, **aggregate-only** — emit cadence patterns and backlog counts, never titles/attendees/reminder text); `FocusModeSource` (Intents `INFocusStatusCenter`); `RecentDocumentsSource` (macOS `~/Library/Application Support/com.apple.sharedfilelist/`); `HealthSleepSource` (iOS `HealthKit`, gated). All carry `Sensitivity.high` so default `PersonalizationDepth` profiles below `.deep` skip them. (A `MusicKit` music-history source and a `FamilyControls`/`DeviceActivity` Screen Time source are planned — the `musicLibraryRead` / `screenTimeRead` permission cases exist for them — but the source structs are not yet implemented.)
- **`SwooshUI`** is shared SwiftUI for both `App/SwooshApp.swift` (menu-bar app via `MenuBarExtra`) and the iOS app. Subfolders: `MenuBar/` (popover + customizer), `Toolbar/` (window toolbar), `ContextMenus/`, `Themes/` (live theme editor, mesh gradients, symbol effects, choreography), `Tips/` (TipKit onboarding), `Interactions/` (drag-drop transferables, scroll/hover, native EditCommands), `Inspector/` (side-panel detail), `Spatial/` (RealityView agent orb + `Model3D` hero), `Spotlight/` (`CoreSpotlight` indexer), `Focus/` (`SetFocusFilterIntent`), `LiveActivities/` (`ActivityKit` Dynamic Island), `AppleIntelligence/` (`WritingTools` composer + Image Playground), `GenerativeSurfaces/` (host bridge for `SwooshGenerativeUI`). **`SwooshWidgets`** provides the widget extension hosted from `WidgetExtension/`.
- **`SwooshGenerativeUI`** is the agent-to-UI layer modeled after Google's A2UI: typed `UIComponent` enum, flat `UISurfaceUpdate` wire format addressed by string IDs, `ComponentCatalog` security gate (only registered types render), a SwiftUI `UIRenderer` that walks the tree, and a sentinel envelope (`_swoosh_ui` JSON key) so tools can return UI inside their normal `JSONValue` output. The host's `GenerativeSurfaceHost` (in `SwooshUI/GenerativeSurfaces/`) accepts surfaces and routes `UIAction`s back to tool calls, approvals, and surface switches.
Split into multiple lines. Config files should read like command lists, not paragraphs.
- **`SwooshPlugins` (cross-platform schema) + `SwooshPluginRuntime` (macOS/Linux host)** is the plugin system. Manifests live at `~/.swoosh/plugins/<id>/manifest.json`; bundled demos in `Plugins/<id>/` (HelloSwift, HelloExec, HelloWasm, HelloWasi) are auto-installed (disabled) on first daemon run via `BundledPluginLoader`. `PluginManifest.validate()` rejects manifests with path-traversal IDs (only `[A-Za-z0-9_-]+` allowed), unknown or reserved-admin permissions, and tool permissions outside the plugin's `requestedPermissions` set. `PluginHost` is the lifecycle owner — `install` writes the manifest disabled, `enable` (gated `humanOnly` `pluginEnable`) validates dependencies, grants the plugin's typed permissions on the `SwooshFirewallActor`, calls the Swift plugin's `initialize(manifest:)` lifecycle hook, then bridges tools into `ToolRegistry`; `disable` unregisters tools, calls `dispose()`, and revokes any permission only this plugin held while preserving baseline grants and grants other enabled plugins still need. The four admin permissions (`pluginInstall`/`Uninstall`/`Enable`/`Disable`) are reserved — plugins cannot request them and the model can never invoke them. Plugin tool calls route through ordinary `ToolRegistry.execute` so the firewall + audit + approval pipeline applies unchanged. **Four executors ship**: `SwiftPluginExecutor` (compile-time linked Swift modules via `SwiftPluginEntrypoint` + `SwiftPluginRegistry`, with optional `initialize`/`dispose` lifecycle hooks — reference impl `HelloSwiftPlugin` in `Sources/SwooshDemoPlugins/`); `ExecutablePluginExecutor` (single-shot `Process` spawn per call with stdio JSON-RPC `{"tool", "args"} → {"ok", "output"|"error"}`, sandbox-enforced timeout + maxOutputBytes + scrubbed env, plus macOS `sandbox-exec` SBPL profile that denies network by default and confines writes to `/tmp` + the plugin dir — reference impl `Plugins/HelloExec/main.sh`); `WasmPluginExecutor` (WasmKit-embedded WebAssembly with two ABIs: linear-memory `entrypoint.wasm` for number-crunching exports — reference `Plugins/HelloWasm/plugin.wat` — and WASI Preview 1 `entrypoint.wasiWasm` that runs `_start` with argv `[pluginID, toolName, argsJSON]` and captures stdout — reference `Plugins/HelloWasi/plugin.wat`; both honour `sandbox.maxWasmMemoryPages` / `maxWasmTableElements` via `Store.resourceLimiter`); `MCPBridgePluginExecutor` (proxies plugin tool calls to an existing MCP server profile via `MCPServerRegistry` + `MCPConnector`). The daemon exposes `/api/plugins/*` and the CLI exposes `swoosh plugin {list,status,install,uninstall,enable,disable}`. **elizaOS-compatible manifest fields** (not a TypeScript runtime): `PluginToolManifest` carries `similes`/`examples`/`tags`; `PluginManifest` carries `dependencies`/`priority`; the decoder accepts `actions` as an alias for `tools` so an elizaOS-shaped manifest can be ingested without rewriting (canonical output stays `tools`). This is *metadata convergence only* — an actual elizaOS plugin package (a TypeScript module exporting `{actions, providers, services}`) still needs a JS runtime to execute, which Swoosh deliberately does not ship; the alignment makes manifests portable, not handlers.
- **`SwooshNetworkPolicy`** is the per-host outbound HTTP gate. `EgressGate` actor evaluates an allow/deny policy against every outbound request that flows through `PolicyEnforcedURLSession` and fans denials to `AuditLogging`. Composes with `SwooshFirewall`'s coarse `.networkAccess` permission — firewall says "may this tool use the network at all", network policy says "may this specific host/scheme be reached for this purpose."
- **`SwooshActantBackend`** is a single-file conformance shim that lets `ActantAgent.MemoryStore`, `ActantAgent.ApprovalCenter`, and per-call adapters over `ActantAgent.Session<ChatMessage>` + `ActantAgent.Auditor<ResponseAuditRecord>` satisfy `SwooshCore`'s five protocols. The shape is "one-line extensions, no adapter classes" — under 100 LoC for the whole module. Audit records ride the same ledger as messages via the auditor's JSON sentinel envelope so Studio + replay see them natively.

The CLI (`Sources/SwooshCLI`) uses `swift-argument-parser`; entry point is `SwooshCommand.swift` with subcommands split across `SetupCommands.swift`, `ChatAskCommands.swift`, `ScoutMemoryCommands.swift`, `ProviderCommands.swift`. Default subcommand is `chat`.

## Self-improvement pillars

Inspired by Hermes Agent's five-pillar model. Three pillars are first-class in Swoosh; they reuse the existing trust + audit + replay invariants instead of rebuilding them from scratch.

- **Skills (`SwooshSkills`)** — typed `SkillDocument` (title, description, body, category, triggerPatterns, steps, platforms, workflowID, etc.) with a `SkillTrust` gate: `draft → reviewed → promoted → frozen` (plus `rejected`). Only `SkillTrust.promptable` (`reviewed`+) entries enter the agent's prompt — drafts sit in an inbox and never reach the model, matching the existing "rejected memory candidates NEVER enter prompts" rule. Bundled `.md` skills (YAML frontmatter + markdown body) live in `Skills/Bundled/` and are loaded by `BundledSkillLoader` (deterministic IDs of the form `bundled.<filename>`). Catalog injection is **Level-0 progressive disclosure**: only `(id, title, description)` per skill enters the system prompt; the model pulls the body via `skill_get`. Tool surface: `skill_list`, `skill_get`, `skill_search`, `skill_propose` (model-writable, lands as `.draft`), `skill_approve` (`humanOnly` — only a user can promote a draft).
- **Goals (`SwooshGoals`)** — typed `Goal` (statement, state ∈ {pending, active, paused, completed, abandoned}, `maxIterations`, iteration log of `GoalIteration` with judge verdict + rationale). `GoalRunner` is an actor with a fully-implemented iteration loop; the agent-turn and judge callbacks are injected closures so the module stays free of model-provider deps. Default judge is a sentinel-heuristic stub (`GOAL_DONE` / `[stuck]` / `[needs-user]`) — wire a real judge model when the daemon gets a real provider. Tool surface: `goal_set`, `goal_status`, `goal_abandon` (`humanOnly`).
- **Manifesting (`SwooshManifesting`)** — Swoosh's name for "dreaming." A scheduled background pass that mines the audit log, drafts skill / memory candidates, and writes a durable report. Pipeline is a deterministic phase list: `gather → mine → propose → consolidate → summarize`. Each pass produces one `Manifestation` record (with full phase trace, proposals, and human-readable summary). **Nothing is auto-applied** — every proposal lands in the user's review inbox, same trust contract as Scout memory candidates. `ManifestationScheduler` policy fires on a daily floor + optional idle threshold + Focus mode awareness. Tool surface: `manifest_now` (`humanOnly`), `manifest_history`, `manifest_get`.

Split into multiple lines. Config files should read like command lists, not paragraphs.

Registration: `DefaultToolRegistrar.registerAll(into:dependencies:selfImprovement:)` takes a new optional `SelfImprovementDependencies` (`skills:`, `goals:`, `manifest:`). Passing `nil` for any field skips that pillar — callers opt in by constructing the matching `*ToolDependencies` and the runtime stores. Permission cases live in `SwooshPermission`: `skillsRead`/`skillsWrite`, `goalsRead`/`goalsWrite`, `manifestRead`/`manifestRun`. Daemon wiring: `swooshd` constructs `FileSkillStore` + `InMemoryGoalStore` + `InMemoryManifestationStore` at startup, runs `BundledSkillLoader` against `Skills/Bundled/` (loads the bundled markdown skills into the store with deterministic IDs of the form `bundled.<filename>`), and starts the `AppUsageRecorder` so the personalization signal accumulates while the daemon runs. The Scout personal-data permissions (`focusModeRead`, `appUsageRead`, `screenTimeRead`, `healthSleepRead`, `healthActivityRead`, `musicLibraryRead`, `photosRead`, `recentDocumentsRead`) gate the matching sources at scan time through `ScoutSource.checkPermission` / `requestPermission`.

## Storage & secrets

- All durable agent state — sessions, memories, approvals, audit records — lives in **ActantDB** at `~/.swoosh/actant.db`, fronted by `actantdb serve` (spawned by `swooshd` via `ActantAgent.ActantDBSupervisor`). Schema sketch in `Docs/Architecture.md`.
- A handful of subsystems (`SwooshVault`, `SwooshFirewall`) still use `SQLite.swift` directly for local caches that don't belong on the event ledger; that's why the `SQLite.swift` package dependency stays.
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
Add an exception path (e.g., 'unless the user explicitly requests it') or escalation ('ask the user for confirmation').
8. `humanOnly` tools cannot be executed by model-origin calls; the model cannot approve its own tool calls.

## Conventions

- Concurrency: actors for stateful subsystems (`AgentKernel`, `SwooshFirewallActor`, `SwooshAuditLog`, `ToolRegistry`). Everything crossing actor boundaries is `Sendable`.
- File headers carry a one-line purpose + the 0.4A/0.4B/etc. version tag — keep this style when adding new files in an existing module.
Write it as "**LOC (Full Name Here)**" on first mention.
- `SwooshPermission` is a string-raw enum; add new permission cases in `SwooshTools/SwooshPermission.swift` and update `Docs/PermissionModel.md`.
- When adding a new toolset family, also add its case to `ToolsetID` and a `register<Name>` hook in `SwooshToolsets/Exports.swift` (the registrar).
- Apps live in three places: `App/` (menu-bar macOS target wired through XcodeGen), `Apps/SwooshMac` (SwiftPM-built standalone Mac shell) and `Apps/SwooshiOS` (the real iOS companion app — `SwooshiOSApp` + `RootView`/`ChatView`/`SettingsView`/`ClientSession`, wired through the XcodeGen `SwooshiOS` target), `Apps/SwooshDashboard` (currently empty scaffold). The iOS app deliberately imports only `SwooshClient` — never `SwooshKit` — so the daemon's `Process`-using deps don't break the build.
Write it as "**POST (Full Name Here)**" on first mention.

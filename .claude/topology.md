# Topology baseline (for the `plumber` subagent)

Swoosh is **SwiftPM** (~47 library modules in `Sources/`, mirrored by ~23 test
targets) plus XcodeGen app/extension targets (`project.yml`). The module
dependency graph in `Package.swift` is **authoritative and compile-enforced**:
a target cannot `import` a module it doesn't declare, and circular target deps
are rejected at resolve time. So `swift build` is the module-level
illegal-import gate and the module-cycle gate. `Scripts/check-flow.sh` guards
the edges SwiftPM can't express (see below).

## Layers & ownership (surface → adapter → use case → domain → port → adapter)

- **Surface (macOS app):** `App/SwooshApp.swift` (menu-bar app; also hosts the
  agent runtime in-process via `SwooshDaemon.start()` — it IS the daemon).
- **Surface (iOS):** `Apps/SwooshiOS/**` — thin HTTP client. Imports only the
  iOS-safe slice (SwooshClient/UI/Wallet/STT/Voice/LocalLLM/GenerativeUI/
  Capabilities/Music). NEVER the daemon/Process modules.
- **Surface (CLI/TUI):** `Sources/SwooshCLI`, `Sources/SwooshTUI`.
- **Boundary adapters:** `Sources/SwooshAPI` (Hummingbird HTTP server,
  `/api/*`), `Sources/SwooshClient` (URLSession client + the wire format),
  `Sources/SwooshProviderBridge` (`ProviderRouter` → `SwooshCore.ModelProvider`).
- **Application/use case:** `Sources/SwooshKit` (`Swoosh.configure`),
  `Sources/SwooshCore` (`AgentKernel.run`, `AgentToolLoop`).
- **Domain/policy:** `Sources/SwooshCore` (`PromptBuilder` privacy boundary;
  `ModelProvider` port), `Sources/SwooshTools` (typed `SwooshTool` contract,
  `SwooshPermission`), `Sources/SwooshFirewall` (`SwooshFirewallActor` — the
  sole permission gate).
- **Ports/interfaces:** `SwooshCore.ModelProvider`; the five protocols
  `SwooshActantBackend` satisfies (MemoryStore / Session / Auditor /
  ApprovalCenter); `SwooshTools` protocols (Firewall, AuditLogging,
  SecretResolving, …).
- **Implementation adapters:** `Sources/SwooshProviders` (OpenAI/Anthropic/
  OpenRouter/Codex/DetourCloud/LocalOpenAI/dev-proxy), `Sources/SwooshToolsets`
  (concrete tools), `Sources/SwooshActantBackend` (ActantDB),
  `Sources/SwooshStorage` (SQLite), `Sources/SwooshPluginRuntime`.

## Canonical lanes

```
iOS surface     : Apps/SwooshiOS -> SwooshClient (wire types + SwooshAPIClient) --HTTP--> app-hosted SwooshAPI
chat (in-app)   : SwooshAPI /api/agent/chat -> SwooshCore.AgentToolLoop/AgentKernel -> ModelProvider (port)
                                                                    -> ProviderBridgeAdapter -> ProviderRouter -> SwooshProviders adapter
tool call       : AgentToolLoop -> ToolRegistry.execute -> SwooshFirewallActor.require (gate) -> SwooshTool (SwooshToolsets)
CLI one-shot    : SwooshCLI -> SwooshKit.configure -> AgentKernel -> ModelProvider -> ProviderRouter -> adapter
```

## Single sources of truth (do not re-derive elsewhere)

- **Wire format:** `Sources/SwooshClient/WireTypes.swift` — shared by iOS and
  the in-process server. The only legal cross-process contract.
- **Permission enforcement:** `SwooshFirewallActor.require(...)` — the ONLY
  gate. Tools must not check permissions inline (see CLAUDE.md rule 2).
- **Prompt privacy boundary:** `SwooshCore/PromptBuilder.buildSystemPrompt` —
  only approved memories + setup-report summary + permission summary enter
  prompts. Rejected candidates / raw Scout records / secrets NEVER do.
- **Provider definitions + routes + active selection:** `ProviderFactory` +
  `~/.swoosh/providers.json` (config-driven; `ProviderConfig` in SwooshModels).
- **Runtime lifecycle:** `App/SwooshApp.swift` → `SwooshDaemon.start()` is the
  sole owner. There is NO standalone `swooshd` binary and NO launchd service.

## Known accepted crossings (triage list)

- `Apps/SwooshiOS` importing `SwooshUI` / `SwooshWallet` / `SwooshGenerativeUI`
  etc. is intentional — those modules build for iOS (the iOS-safe slice).
  Forbidden set is only the Process/server/daemon modules.
- `SwooshUI` is shared by the macOS app and iOS; it must stay iOS-buildable
  (no Process / SwooshKit / SwooshDaemon imports).

## The gate

- `Scripts/check-flow.sh` — fast grep guard for: (1) iOS importing a
  daemon/macOS module, (2) domain/data layers (Core/Tools/Models) importing a
  UI framework, (3) SwooshCore importing a concrete adapter/server/UI module.
  Exit non-zero on violation. **Green as of this baseline.** `plumber` runs it
  POST-FLIGHT for graph evidence instead of returning UNKNOWN.
- `swift build` — the module-graph illegal-import + cycle gate (SwiftPM).
- There is no recorded-violation baseline file: the repo is clean, so the gate
  is a hard PASS, not a ratchet over existing debt.

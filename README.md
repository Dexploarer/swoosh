# Swoosh

> **Swoosh is a Swift-native, MLX-capable, Apple-first autonomous agent runtime.**
> Private by default. Typed by design. Local when possible. Auditable always.

Swoosh is not "Hermes rewritten in Swift." It is the **native agent operating layer** for Apple devices and Swift apps — an embeddable SDK, a local daemon, a CLI, and a native macOS/iOS app.

## Shipping Spine

The setup-to-first-use spine is `swoosh setup quick`, provider/doctor checks, Scout scan, memory review, approved-context chat, bearer-gated Mac-to-iPhone chat through `swooshd`, skills, cron jobs, terminal backend selection, and chat adapter toggles.

Swoosh should expose real configured state or explicit missing-configuration status. It must not return empty success JSON that looks connected.

## Strategic architecture

```
SwooshKit          →  Swift SDK for embedding agents into any app
Swoosh.app         →  native macOS/iOS personal agent
swooshd            →  local daemon with permissions, memory, and automations
swoosh CLI         →  developer shell
SwooshMCP          →  import/export MCP tools
SwooshMLX          →  local Apple-silicon model runtime (MLX Swift)
SwooshFoundation   →  Apple Foundation Models structured-output adapter
SwooshFirewall     →  user-visible tool permissions and auditability
SwooshVault        →  transparent, user-governed memory
SwooshFlow         →  testable, replayable workflow engine
SwooshBoard        →  executable multi-agent task graph with replay
SwooshTriggers     →  native event-driven scheduler
SwooshBench        →  practical agent reliability benchmarks
SwooshBridge       →  Python/Node/MCP interop bridge
```

## Module map

| Module | Purpose |
|--------|---------|
| `SwooshKit` | Public SDK — embed agents in any Swift app |
| `SwooshCore` | AgentKernel actor, agent loop, runtime context |
| `SwooshTools` | Typed `Tool` protocol, `Permission` enum, `ToolRegistry` actor |
| `SwooshMacros` | `@SwooshTool` macro infrastructure (experimental — tools currently hand-write conformance) |
| `SwooshFirewall` | Agent Firewall — approval engine, audit log, risk classification |
| `SwooshVault` | Memory Vault — transparent, editable, auditable, confidence-scored |
| `SwooshFlow` | Workflow compiler, "Make this repeatable", test fixtures, failure rules |
| `SwooshBoard` | Executable task graph with typed tasks and replay |
| `SwooshTriggers` | Trigger + action schema and in-memory registry (firing engine experimental) |
| `SwooshModels` | Model catalog + Hugging Face discovery |
| `SwooshMLX` | MLX Swift on-device inference — selectable via `SWOOSH_MLX_MODEL` |
| `SwooshFoundation` | Apple Foundation Models adapter — selectable via `SWOOSH_FOUNDATION_MODEL` |
| `SwooshProviders` | OpenAI, OpenRouter, Eliza Cloud, and local OpenAI-compatible (Ollama / LM Studio) adapters |
| `SwooshBridge` | Python/Node/MCP interop bridge (experimental — transport not yet wired) |
| `SwooshBench` | Reliability benchmarks (tool validity, memory precision, replay determinism) |
| `SwooshUI` | SwiftUI components, Liquid Glass, JSON theme engine |
| `SwooshMCP` | MCP server registry, auth, and policy (client transport experimental) |
| `SwooshLSP` | sourcekit-lsp integration |
| `SwooshAPI` | Hummingbird HTTP API server |
| `SwooshActantBackend` | <100-LoC conformance shim that wires `ActantAgent` into `SwooshCore`'s five protocols |
| `SwooshGenerativeUI` | Agent-emitted UI (A2UI-shaped: typed `UIComponent` enum + `UISurfaceUpdate` + `UIRenderer`) |

**Backend.** All durable state — sessions, memories, audit, approvals, setup
reports — lives in ActantDB, the event-sourced sibling repo at
`/Users/home/actantDB/`. `swooshd` supervises an `actantdb serve` child
process at startup via `ActantAgent.ActantDBSupervisor` and exposes its
URL through `ACTANT_BASE_URL`. The Swift SDK has two layers: low-level
`ActantDB` for raw endpoints, and the opinionated `ActantAgent` facade
(`MemoryStore` / `Session<Message>` / `Auditor<Record>` / `ApprovalCenter` /
`ReplayClient`).

**Implementation status.** The core spine — kernel, providers, firewall,
daemon, ActantDB persistence — is wired and tested. Modules marked
*experimental* above are present but not yet fully wired. See
`Docs/Audit.md` for a current, file-cited readiness assessment (and §9
for remediation progress).

## Quick start

```swift
import SwooshKit

// With no model provider configured, the local diagnostic fallback
// answers — enough to confirm wiring. Plug in a real provider and a
// tool registry to get the full tool-calling agent loop.
let swoosh = try await Swoosh.configure { config in
    // config.modelProvider = myProvider
    // config.toolRegistry  = myRegistry
}

let response = try await swoosh.ask("Audit this repo and list issues.")
print(response.message)
```

## Engineering principles

1. Every tool is typed.
2. Every risky action is permissioned.
3. Every agent step is logged.
4. Every workflow is replayable.
5. Every memory is inspectable.
6. Every skill is testable.
7. Every model route is visible.
8. Every background task is cancellable.
9. Every integration has least-privilege scopes.
10. Every successful repeated task can become a workflow.

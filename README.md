# Swoosh

> **Swoosh is a Swift-native, MLX-capable, Apple-first autonomous agent runtime.**
> Private by default. Typed by design. Local when possible. Auditable always.

**v1 — May 2026.** Swoosh is the native agent operating layer for Apple devices: an embeddable SDK, a local daemon, a CLI, a native macOS menu-bar app, and a real iOS companion. It ships voice in/out, on-device LLM inference, customizable workspaces, generative UI, and pluggable cloud TTS + music generation.

## What v1 ships

| Surface | What it does |
|---|---|
| **macOS menu-bar app** | Click-to-chat tray popover, customizable panels (drag-drop, 36 kinds), ⌥Space voice pill, frameless desktop overlay for agent-emitted UI |
| **Dashboard window** | Responsive 1–4 column grid of panels; density picker; full-screen support |
| **Voice mode** | Hold-to-talk or always-on. STT: Apple Speech (free) or WhisperKit (4 model sizes). TTS: system voices, ElevenLabs, OpenAI, Cartesia (40 ms first-byte). |
| **Music generation** | Suno V5.5 (via sunoapi.org), ElevenLabs Music, Stable Audio. Job-based with polling. |
| **iOS companion** | Same chat surface, same panels, same voice. Push-to-talk, offline-cached transcripts, local LLM fallback (LiteRT-LM Gemma 4 E4B by default) when the Mac daemon is unreachable. |
| **Local LLM on iOS** | Gemma 4 E4B ships by default, with Gemma 4 E2B as the smaller fallback. |
| **Cross-device offline** | Append-only JSONL ledger + outbox queue; messages replay automatically when the daemon comes back. |
| **Provider keys** | One Settings → Voice screen, Keychain-backed, "Get key" deep-links to every provider's dashboard. |

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
SwooshMCP          →  Model Context Protocol client (stdio transport, wired into ToolRegistry)
```

## Module map

| Module | Purpose |
|--------|---------|
| `SwooshKit` | Public SDK — embed agents in any Swift app |
| `SwooshCore` | AgentKernel actor, agent loop, runtime context |
| `SwooshTools` | Typed `Tool` protocol, `Permission` enum, `ToolRegistry` actor |
| `SwooshFirewall` | Agent Firewall — approval engine, audit log, risk classification |
| `SwooshVault` | Memory Vault — transparent, editable, auditable, confidence-scored |
| `SwooshFlow` | Workflow compiler, "Make this repeatable", test fixtures, failure rules |
| `SwooshBoard` | Executable task graph with typed tasks and replay |
| `SwooshModels` | Model catalog (curated + Hugging Face discovery) + hardware-aware recommendations |
| `SwooshMLX` | MLX Swift on-device inference (macOS) |
| `SwooshFoundation` | Apple Foundation Models adapter + `FoundationExecutor` |
| `SwooshLocalLLM` | LiteRT-LM Gemma 4 wrapper, on-device inference for iOS |
| `LiteRTLM` | Vendored Google LiteRT-LM Swift wrapper (Apache 2.0) |
| `SwooshSTT` | Speech-to-text — Apple Speech + WhisperKit + WhisperModelManager |
| `SwooshVoiceProviders` | Cloud TTS adapters (ElevenLabs, OpenAI, Cartesia) + `VoiceRouter` + `StreamingTTSPlayer` + Keychain helpers |
| `SwooshMusic` | Cloud music generation (Suno, ElevenLabs Music, Stable Audio) |
| `SwooshProviders` | Remote LLM adapters (OpenAI, OpenRouter, Eliza Cloud, local OpenAI-compatible) |
| `SwooshUI` | SwiftUI: AgentShell, PanelHost, voice scenes, neon design tokens, themes |
| `SwooshClient` | Cross-platform iOS-safe client: `SwooshAPIClient`, `CachedExecutor`, `OfflineMessageCache` |
| `SwooshMCP` | Model Context Protocol stdio client wired into ToolRegistry |
| `SwooshAPI` | Hummingbird HTTP API server |
| `SwooshActantBackend` | <100-LoC conformance shim wiring `ActantAgent` into `SwooshCore` |
| `SwooshGenerativeUI` | Agent-emitted UI (A2UI-shaped) + shared `SwooshNeonTokens` |

**Backend.** All durable state — sessions, memories, audit, approvals, setup
reports — lives in ActantDB, the event-sourced sibling repo at
`/Users/home/actantDB/`. `swooshd` supervises an `actantdb serve` child
process at startup via `ActantAgent.ActantDBSupervisor` and exposes its
URL through `ACTANT_BASE_URL`. The Swift SDK has two layers: low-level
`ActantDB` for raw endpoints, and the opinionated `ActantAgent` facade
(`MemoryStore` / `Session<Message>` / `Auditor<Record>` / `ApprovalCenter` /
`ReplayClient`).

**Implementation status (v1, May 2026).** Everything in the module map is
wired and tested — **1757 tests in 396 suites, all passing**. Mac app
builds clean; iOS app builds clean for Simulator + device. See
`Docs/CHANGELOG_v1.md` for the per-area breakdown.

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

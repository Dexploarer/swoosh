# Detour — Swoosh Edition

[![CI](https://github.com/Dtour-Stack/swoosh/actions/workflows/ci.yml/badge.svg)](https://github.com/Dtour-Stack/swoosh/actions/workflows/ci.yml)
![Release](https://img.shields.io/github/v/tag/Dtour-Stack/swoosh?label=release&sort=semver)
![Swift 6.3](https://img.shields.io/badge/Swift-6.3-orange.svg)
![Platforms](https://img.shields.io/badge/platforms-macOS%2026%20·%20iOS%2026-blue.svg)
![Architecture](https://img.shields.io/badge/concurrency-Sendable--clean%20actors-green.svg)

> **A Swift-native, MLX-capable, Apple-first autonomous agent runtime.**
> Private by default. Typed by design. Local when possible. Auditable always.

**Detour** is the product; **Swoosh** is the runtime/SDK and codebase it's built on. (This is the *Swoosh Edition* line.)

Swoosh is the native agent operating layer for Apple devices: an embeddable SDK (`SwooshKit`), a `swoosh` CLI, and native **macOS menu-bar + iOS companion** apps. The shipping app is branded **Detour**. It runs an agent loop with a typed tool registry, a permission firewall, an inspectable memory vault, replayable workflows, voice in/out, on-device + cloud LLMs, a crypto wallet + launchpad surface, and agent-emitted generative UI.

**The agent runtime runs in-process.** There is no separate `swooshd` daemon to launch — the runtime (kernel, tools, providers, ActantDB) boots inside the macOS app and inside the `swoosh` CLI. The iPhone is a thin HTTP client that pairs to the Mac. (`swoosh daemon pair` exists only to pair an iPhone; launch/quit the app to start/stop the runtime.)

---

## Install & run

Targets **macOS 26 / iOS 26**, **Swift 6.3** (Xcode 26). No Apple Developer account is required for the SwiftPM and local-macOS paths below.

### CLI + SDK — no signing, no Xcode project needed

```bash
git clone https://github.com/Dtour-Stack/swoosh.git
cd swoosh
swift build                      # build the whole package
swift run swoosh                 # launch the agent (defaults to `chat`)
swift run swoosh setup           # guided first-run setup
swift run swoosh doctor          # environment + provider diagnostics
```

`swoosh` subcommands: `setup · ask · doctor · scout · memory · model · daemon · chat · self-test · permissions · provider · skills · cron · terminal · chat-adapters · plugin · goal · manifest · completions` (default: `chat`).

### macOS menu-bar app — runs with a free Apple ID

The Xcode project is **generated** from `project.yml` via [XcodeGen]; don't edit `.xcodeproj` directly.

```bash
brew install xcodegen          # once
xcodegen generate              # regenerate Swoosh.xcodeproj from project.yml
open Swoosh.xcodeproj          # then: select the “Swoosh” scheme → set Signing
                               # to your own team (a free Apple ID works for
                               # running locally) → ⌘R
```

Compile-check the app without any signing:

```bash
xcodebuild -project Swoosh.xcodeproj -scheme Swoosh -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO build
```

### iOS companion

```bash
xcodebuild -project Swoosh.xcodeproj -scheme SwooshiOS \
  -destination 'generic/platform=iOS Simulator' build      # Simulator: free Apple ID
```

> Installing on a **physical iPhone** or distributing the app needs a **paid Apple Developer account** for a device provisioning profile. The Simulator and local-macOS runs do not. The iOS app pairs to the Mac with a bearer token (Settings → host + token); it imports only `SwooshClient`, never the macOS-only runtime.

### Embed the SDK

```swift
import SwooshKit

// With no model provider configured, a local diagnostic fallback answers —
// enough to confirm wiring. Plug in a provider + tool registry for the full
// tool-calling agent loop.
let swoosh = try await Swoosh.configure { config in
    // config.modelProvider = myProvider
    // config.toolRegistry  = myRegistry
}
let response = try await swoosh.ask("Audit this repo and list issues.")
print(response.message)
```

---

## What it ships

| Surface | What it does |
|---|---|
| **macOS menu-bar app (Detour)** | Click-to-chat tray with 5 panels (Chat / Cloud / Wallet / Calendar / Usage); primary dashboard window; ⌥Space voice; frameless overlay for agent-emitted UI |
| **Dashboard** | Chat, Memories, Skills, **Safety**, **Approvals**, **Firewall**, Gaming, Wallet, Launchpads, Models, Tools, Audit, Settings — all backed by the in-process runtime over a local HTTP API |
| **Agent & Safety** | Permission-preset picker (Safe→Autonomous) and the enforced safety flags (autonomous trading, mainnet writes, model self-approval, …) as live toggles |
| **Approvals & Firewall** | Human-in-the-loop approval queue (approve once / for session / deny) and the live permission-grant list (revoke) — the firewall is the sole enforcement point |
| **Memory** | Inspectable, confidence-scored candidates with per-row + bulk Approve and a toast prompt; nothing enters prompts until you approve it |
| **Wallet** | Create Solana / EVM accounts (keys stay in Keychain), live balances, holdings |
| **Launchpads** | Token-launch form (logo upload, socials, dev-buy). **pump.fun** runs in *prepare* mode (pins IPFS metadata, no broadcast); execution is gated, audited, and approval-required |
| **Voice** | Hold-to-talk or always-on. STT: Apple Speech or WhisperKit. TTS: system, ElevenLabs, OpenAI, Cartesia |
| **Providers** | OpenAI, OpenRouter, Anthropic, Codex CLI, Detour Cloud, local OpenAI-compatible, on-device MLX + Apple Foundation Models — config-driven with live switching |
| **Plugins** | Swift / executable / WebAssembly (WASM + WASI) / MCP-bridge executors, sandboxed and permission-gated |
| **Self-improvement** | Skills, Goals, and Manifesting (“dreaming”) — durable, reviewable, on the same audit/replay path |

---

## Architecture

~47 single-purpose, `Sendable`-clean modules. The agent kernel, firewall, tool registry, and ActantDB all run **in-process**.

```
SwooshKit ──► SwooshCore ──► SwooshTools ──► SwooshToolsets
   │              ▲                              │
   ▼              │                              ▼
SwooshActantBackend ─► ActantAgent ─► ActantDB   SwooshFirewall (sole permission gate)
SwooshUI / SwooshGenerativeUI (design tokens, leaf)   SwooshFlow / SwooshNetworkPolicy / …
SwooshClient (iOS-safe transport) ◄── Apps/SwooshiOS
```

| Module | Purpose |
|--------|---------|
| `SwooshKit` | Public SDK — embed agents in any Swift app (macOS/Linux) |
| `SwooshCore` | `AgentKernel` actor, agent + tool loop, `PromptBuilder` privacy boundary |
| `SwooshTools` / `SwooshToolsets` | Typed `SwooshTool`, `ToolRegistry`, `SwooshPermission`; concrete tool families (files, git, EVM, Solana, Jupiter, Hyperliquid, launchpads, …) |
| `SwooshFirewall` | The **only** permission enforcement point; in-memory audit log |
| `SwooshFlow` | Replayable / dry-runnable / trigger-dispatched workflow engine |
| `SwooshProviders` / `SwooshMLX` / `SwooshFoundation` | Remote LLM adapters · on-device MLX · Apple Foundation Models |
| `SwooshScout` | Personalization scanner → redactor → candidate review (opt-in, sensitivity-gated) |
| `SwooshUI` / `SwooshGenerativeUI` | Shared SwiftUI + the **Volt Paper** design tokens (`SwooshGenerativeUI` is a dependency-free leaf) |
| `SwooshClient` | Cross-platform, iOS-safe transport (`SwooshAPIClient`, wire types) — the only thing the iOS app imports |
| `SwooshDaemon` / `SwooshAPI` | In-process runtime host (library) + Hummingbird HTTP API |
| `SwooshActantBackend` | <100-LoC shim wiring `ActantAgent` into `SwooshCore`'s stores |
| `SwooshWallet` / `SwooshNetworkPolicy` | Wallet accounts + signing · per-host outbound egress gate |
| `SwooshSkills` / `SwooshGoals` / `SwooshManifesting` | Self-improvement pillars |
| `SwooshPlugins` / `SwooshPluginRuntime` | Plugin schema + host (Swift / exec / WASM / MCP) |

**Backend.** All durable state — sessions, memories, audit, approvals, setup reports — lives in **ActantDB** (event-sourced, at `~/.swoosh/actant.db`), spawned in-process as an `actantdb serve` child. Secrets live in Keychain (`ai.swoosh.agent`).

---

## Engineering principles (enforced in code + CI)

1. Every tool is typed (`Codable & Sendable` I/O).
2. Every risky action is permissioned (via `SwooshFirewallActor.require`).
3. Every agent step is logged (`AuditEntry`).
4. Every workflow is replayable.
5. Every memory is inspectable; rejected candidates / secrets / cookies **never** enter prompts.
6. Crypto tools never accept private keys or seed phrases as input.
7. `humanOnly` tools cannot be executed by the model; the model cannot approve its own calls.
8. Module boundaries are enforced by `Package.swift` + `Scripts/check-flow.sh` (the topology gate).

## Building & testing

```bash
swift build                       # build everything
./Scripts/swift-test-safe.sh      # full suite via the orphan-safe wrapper (use this, not raw `swift test`)
./Scripts/check-flow.sh           # fast topology / layering gate
```

CI (`.github/workflows/ci.yml`) runs the topology gate on every push and the full build + test suite on macOS. Contributions should keep `swift build`, the test suite, and `check-flow.sh` green.

[XcodeGen]: https://github.com/yonaskolb/XcodeGen

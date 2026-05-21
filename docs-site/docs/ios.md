---
id: ios
title: iOS & Kernel Sync
sidebar_position: 8
---

# iOS & Kernel Sync

## Current model — thin client

The first iOS slice (`Apps/SwooshiOS`) makes the iPhone a thin HTTP client to `swooshd` on the Mac.

**Architecture:**

```
iPhone (SwooshiOS)
  └── SwooshAPIClient (URLSession)
        └── /api/agent/chat   (bearer-gated HTTP)
              └── swooshd (Mac)
                    └── AgentKernel (single kernel, all state)
```

**Current capabilities:**

| Feature | Status |
|---------|--------|
| Chat via `/api/agent/chat` | ✅ Working |
| Settings / Pairing screen | ✅ Working |
| Connections screen | ✅ Working |
| Bearer token auth | ✅ Required |
| Bonjour discovery | 🔲 Near-term |
| Token streaming | 🔲 Not yet |
| Approvals / audit UI | 🔲 Not yet |
| On-device MLX | 🔲 Roadmap |

**Limitations (deliberate for this slice):**

- Synchronous chat only — no token streaming.
- No Bonjour discovery yet; pairing requires you to enter the Mac's IP/hostname manually.
- No on-device MLX path.
- No approvals/audit UI on iOS.
- Assumes Mac and iPhone are on the same Wi-Fi.

## Pairing

1. Start `swooshd` with `SWOOSH_HOST=0.0.0.0`:
   ```bash
   SWOOSH_HOST=0.0.0.0 swift run swooshd
   ```
2. Copy the token from `~/.swoosh/api_token`.
3. In SwooshiOS, open the drawer → **Settings → Pairing**.
4. Enter `http://<your-mac>.local:8787` and paste the token.
5. Tap **Pair**.

## Roadmap — embedded iOS kernel

The long-term design removes the Mac dependency for everyday iPhone use.

### Goals

- The iPhone can chat with full agent identity when the Mac is off or out of range.
- The Mac is preferred when reachable (bigger MLX models, full provider keys, real tools) but never required.
- There is still **one agent** — both devices share the same memories, audit log, and approvals.

### Architecture

```
            ┌──────────────────────────────────────────────────┐
            │  ActantDB Swift SDK (sdks/swift/)                │
            │  ─────────────────────────────────────────────── │
            │  Mode A: remote HTTP   (existing — Mac CLI)       │
            │  Mode B: spawn local   (existing — swooshd boot)  │
            │  Mode C: embed via FFI (NEW — required for iOS)   │
            │  + sync primitives: events_since() / ingest()     │
            └──────────────────────────────────────────────────┘
                    ▲                          ▲
                    │                          │
            ┌───────┴──────┐            ┌──────┴───────┐
            │   Swoosh     │            │   Swoosh     │
            │   (macOS)    │            │   (iOS)      │
            │   Mode A or B│            │   Mode C only│
            └──────────────┘            └──────────────┘
                    \                       /
                     \                     /
                      \   CloudKit zone   /
                       \  (sync substrate)/
                        \________________/
```

### What's already landed

| Component | Status |
|-----------|--------|
| `SwooshExecutor` protocol (abstract chat backend) | ✅ Landed |
| `RemoteKernelExecutor` (HTTP to daemon) | ✅ Landed |
| `LocalKernelExecutor` (in-process kernel, Mac only) | ✅ Landed |
| `ToolPlatform` metadata — iOS sees only `.iOS`-tagged tools | ✅ Landed |
| Files/Git/SwiftDev toolsets tagged Mac-only | ✅ Landed |

### What's pending

| Component | Notes |
|-----------|-------|
| ActantDB FFI surface (uniffi-rs) | ActantDB repo work |
| iOS-clean Rust core (no `Process`, sandbox-safe paths) | ActantDB repo work |
| `XCFramework` packaging for iOS | ActantDB CI work |
| HLC timestamps + content-derived event IDs | Replication pre-req |
| `events(since:)` + `ingest(_:)` sync primitives | ActantDB SDK work |
| `ActantSync` CloudKit actor | Swoosh + ActantDB shared |
| `RoutedExecutor` (Mac-preferred, iPhone fallback) | Swoosh — trivial once FFI lands |

### Sync design

Two new ActantDB SDK methods drive sync:

```swift
// Pull all events after a cursor (nil = "all events from the beginning")
func events(since cursor: SyncCursor?) async throws -> EventBatch

// Idempotent ingest — duplicate event IDs silently skipped
func ingest(_ events: [Event]) async throws -> IngestSummary
```

Conflict policy: **last-writer-wins by HLC** per record type. Append-only logs are merge-conflict-free by construction; state projections (e.g., "is this memory approved?") follow LWW.

## `SwooshClient` module

`SwooshClient` is the cross-platform thin client SDK (iOS + macOS). It has **zero internal dependencies** — no `Foundation.Process`, no Hummingbird — so it builds for any Apple platform.

Contents:

| Type | Purpose |
|------|---------|
| `ChatRequest` / `ChatResponse` | JSON wire format |
| `APIErrorBody` | Structured error envelope |
| `APIVersion` | Version negotiation |
| `SwooshAPIClient` | `URLSession`-backed actor |
| `TokenStore` | iOS Keychain + macOS Keychain token persistence |
| `HostStore` | `UserDefaults`-backed host URL persistence |
| `SwooshExecutor` | Abstract chat backend protocol |
| `RemoteKernelExecutor` | HTTP implementation |

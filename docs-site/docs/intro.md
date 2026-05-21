---
id: intro
title: Introduction
sidebar_position: 1
---

# Swoosh

> **Swift-native, MLX-capable, Apple-first autonomous agent runtime.**
> Private by default. Typed by design. Local when possible. Auditable always.

Swoosh is the native agent operating layer for Apple devices and Swift apps — an embeddable SDK, a local daemon, a CLI, and a native macOS/iOS app.

## What ships

| Component | Description |
|-----------|-------------|
| **`SwooshKit`** | Swift SDK — embed agents in any Swift app |
| **`swoosh` CLI** | Developer shell: chat, setup, diagnostics, memory |
| **`swooshd`** | Local daemon with permissions, memory, and automations |
| **Swoosh.app** | Native macOS menu-bar app |
| **SwooshiOS** | Thin companion app for iPhone |

The Mac is the hub: it runs the kernel, tools, providers, and storage. The iPhone is a thin client over HTTP (with a fully embedded kernel on the roadmap).

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

## Quick start

```swift
import SwooshKit

let swoosh = try await Swoosh.configure { config in
    // config.modelProvider = myProvider
    // config.toolRegistry  = myRegistry
}

let response = try await swoosh.ask("Audit this repo and list issues.")
print(response.message)
```

With no provider configured, the local diagnostic fallback answers — enough to confirm wiring. Plug in a real provider for the full tool-calling loop.

## Next steps

- [Getting Started](./getting-started) — build from source, first run, daemon, iPhone pairing
- [Architecture](./architecture) — process model, module map, storage layout
- [CLI Reference](./cli) — every subcommand and flag
- [Permissions](./permissions) — firewall, profiles, safety config

---
name: iOS Daemon Pairing
description: Keep Swoosh's iPhone client, Mac daemon, bearer auth, and shared wire types aligned
category: coding
tags: [ios, daemon, api, client]
trust: promoted
platforms: [macOS, iOS]
triggers: ["ios app", "swooshclient", "daemon api", "bearer token", "pairing"]
---

## When to use

Use this when changing `SwooshClient`, `SwooshAPI`, `SwooshDaemon`, or `Apps/SwooshiOS`.

## Procedure

1. Keep `SwooshClient` free of internal Swoosh dependencies.
2. Keep `SwooshKit` out of the iOS app.
3. Keep `swooshd` as the single `AgentKernel` owner.
4. Keep request and response wire types in `Sources/SwooshClient/WireTypes.swift`.
5. Verify bearer auth behavior before UI polish.
6. Run the SwooshiOS simulator build with `CODE_SIGNING_ALLOWED=NO`.

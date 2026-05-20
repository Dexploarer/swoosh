---
name: Swift Concurrency Triage
description: Diagnose Swift 6 Sendable, actor isolation, and async boundary failures in Swoosh
category: debugging
tags: [swift, concurrency, sendable, actors]
trust: promoted
platforms: [macOS, linux]
triggers: ["sendable error", "actor isolation", "swift build failed", "concurrency warning"]
---

## When to use

Use this when Swift 6.3 reports a `Sendable`, actor-isolation, or async boundary error.

## Procedure

1. Identify the module boundary first. Do not patch a callsite until you know which target owns the type.
2. Prefer actor ownership for mutable shared state.
3. Prefer concrete `Sendable` value types over casts, erased containers, or widened unions.
4. If the failure crosses an external boundary, validate once there and keep the inner API strongly typed.
5. Add a focused test when the fix changes actor behavior, tool execution, or request routing.

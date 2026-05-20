---
name: Swoosh Safety Review
description: Review prompt, memory, permission, API, and tool changes for Swoosh safety invariants
category: coding
tags: [security, permissions, prompts, tools]
trust: promoted
platforms: [macOS, linux]
triggers: ["security review", "permission change", "prompt builder", "tool approval", "api auth"]
---

## When to use

Use this when a change touches `PromptBuilder`, Scout, memories, approvals, tool execution, crypto tools, secrets, or `/api/*` daemon routes.

## Procedure

1. Verify external inputs are validated at the route, CLI, file, or API boundary.
2. Verify tool execution goes through `SwooshFirewall`.
3. Verify `humanOnly` tools cannot be executed by model-origin calls.
4. Verify secrets, cookies, raw Scout records, rejected memories, and private keys cannot enter prompts or audit summaries.
5. Verify API routes require bearer auth, and tokenless daemon startup denies `/api/*`.
6. Add focused tests for any changed security or permission behavior.

---
name: swoosh-security-review
description: Review Swoosh tool, permission, prompt, and daemon API changes for safety regressions.
---
# Swoosh Security Review Skill

Use this when work touches tools, permissions, prompt assembly, Scout data, secrets, crypto, API auth, or the daemon boundary.

## Instructions

1. Check that external input is validated at the route, transport, CLI, or file boundary.
2. Check that tool execution goes through `SwooshFirewall`.
3. Check that `humanOnly` tools cannot be called by model-origin requests.
4. Check that secrets, cookies, private keys, raw Scout records, and rejected memory candidates cannot enter prompts.
5. Check that `/api/*` routes require bearer auth or deny all requests when no token exists.

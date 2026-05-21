# SwooshFirewall

This is the **only** permission enforcement point in Swoosh. Loaded automatically when Claude edits files here.

## Hard rules

- **No bypass paths.** Every tool dispatch goes through `SwooshFirewallActor.require(permission)`. There is no "skip if env=dev" branch. There is no "log-only mode." If you need a permissionless mode, the answer is to add a permission case set to default-allow, not to skip the firewall.
- **Default-deny.** Unknown permissions deny. Don't add a "fail open" path on parsing errors.
- **Audit before allow.** Every `require` call produces an `AuditEntry` via `AuditLogging` — both grants and denies. The audit log is the answer to "/why did this happen."
- **Constant-time wherever a token, signature, or HMAC is compared.** No `==` on secrets.

## Common edits and what they imply

- Adding a permission case → also update `Sources/SwooshTools/SwooshPermission.swift` and `Docs/PermissionModel.md`. The three must stay in sync.
- Changing the `AuditEntry` schema → check `SwooshActantBackend/` for the auditor sentinel envelope; the ledger must still parse old entries (append-only).
- New deny reason → add a test in `Tests/SwooshFirewallTests/FirewallTests.swift` exercising the deny path.

## What never goes through here

`PromptBuilder` is a separate boundary (the **privacy** boundary). Don't fold prompt content gating into the firewall. They are deliberately separate so the firewall can be reasoned about as "tool dispatch only."

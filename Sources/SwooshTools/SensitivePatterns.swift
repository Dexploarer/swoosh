// SwooshTools/SensitivePatterns.swift — Shared substrings flagged for redaction — 0.9A
//
// Single source of truth for "this looks like a secret, redact it before
// it lands in audit logs / prompts / MCP responses". Consumed by both
// `SwooshPlugins.PluginContentRedactor` and `SwooshMCP.MCPContentRedactor`.
//
// Adding a new sensitive token here covers every consumer at once — the
// previous design kept byte-identical lists in two modules, which meant a
// new pattern added in one place silently leaked in the other.
//
// The list deliberately uses substring patterns (matched case-sensitively
// against the original content). Redactors that need additional
// context-sensitive rules (regex anchors, header-boundary checks) layer
// those on top — `SensitivePatterns.strings` is the floor, not the ceiling.

import Foundation

public enum SensitivePatterns {
    /// Substrings whose presence in tool / MCP / plugin output should
    /// trigger redaction. Ordered by specificity: PEM headers and prefix
    /// markers first (cheapest substring match), then key-value indicators.
    public static let strings: [String] = [
        "-----BEGIN",
        "PRIVATE KEY",
        "sk_",
        "xprv",
        "xpub",
        "seed:",
        "mnemonic:",
        "cookie:",
        "session_token",
        "password:",
        "secret:",
        "Bearer ",
        "api_key:",
        "token:",
    ]
}

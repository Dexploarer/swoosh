// SwooshTools/SensitivePatterns.swift — Shared sensitive-substring redaction — 0.9C
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
// context-sensitive rules (e.g. byte-cap truncation) layer those on top —
// `SensitivePatterns.redact(_:)` is the canonical masker; the strings list
// is the floor of patterns it watches for.

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
        "token:"
    ]

    /// Characters that terminate a sensitive value. The masker consumes
    /// every non-terminator character after a pattern hit so the value
    /// itself is masked, not just the label — `Bearer eyJ...` becomes
    /// `[REDACTED]`, not `[REDACTED]eyJ...`.
    private static let valueTerminators: Set<Character> = [
        " ", "\t", "\n", "\r", ",", ";", "\"", "'", ")", "]", "}"
    ]

    /// Mask every occurrence of every pattern in `strings` plus the value
    /// that follows it. Replacement is the single token `[REDACTED]` —
    /// both label and value collapse to one marker.
    ///
    /// After a pattern hit, the masker:
    ///   1. Advances past the pattern itself.
    ///   2. Skips any *leading* terminators (so `token: secret` doesn't
    ///      stop at the space and leak `secret` — patterns without a
    ///      trailing whitespace literal still mask the value).
    ///   3. Consumes non-terminator characters until the next terminator
    ///      or end-of-string.
    ///
    /// Why "consume to terminator" instead of regex word boundary: real
    /// tokens contain `.` and `-` (JWT segments, Solana addresses,
    /// `xprv...` strings) so `\b` would stop too early. The terminator
    /// set is intentionally narrow — whitespace, quote chars, JSON/CSV
    /// delimiters — to cover line-based logs, JSON payloads, and HTTP
    /// header dumps without truncating inside a token.
    public static func redact(_ text: String) -> String {
        var output = ""
        output.reserveCapacity(text.count)
        let scalars = text.unicodeScalars
        var current = scalars.startIndex
        while current < scalars.endIndex {
            if let match = firstMatchAt(scalars: scalars, start: current) {
                output += "[REDACTED]"
                current = consumeValue(
                    scalars: scalars,
                    afterPatternAt: scalars.index(current, offsetBy: match.scalarCount)
                )
            } else {
                output.unicodeScalars.append(scalars[current])
                current = scalars.index(after: current)
            }
        }
        return output
    }

    /// Skip leading terminators (so `label:_value` and `label: value` both
    /// mask the value, not just the label) then walk through the value
    /// itself until a trailing terminator or end-of-string. Returns the
    /// index AFTER the masked value.
    private static func consumeValue(
        scalars: String.UnicodeScalarView,
        afterPatternAt: String.UnicodeScalarView.Index
    ) -> String.UnicodeScalarView.Index {
        var cursor = afterPatternAt
        while cursor < scalars.endIndex, valueTerminators.contains(Character(scalars[cursor])) {
            cursor = scalars.index(after: cursor)
        }
        while cursor < scalars.endIndex, !valueTerminators.contains(Character(scalars[cursor])) {
            cursor = scalars.index(after: cursor)
        }
        return cursor
    }

    /// Returns the pattern that matches at `start` in `scalars`, or nil
    /// if nothing matches. Iterates the canonical list largest-first so
    /// `-----BEGIN` wins over any shorter prefix overlaps.
    private static func firstMatchAt(
        scalars: String.UnicodeScalarView,
        start: String.UnicodeScalarView.Index
    ) -> Match? {
        let remaining = scalars[start...]
        for pattern in strings {
            let patternScalars = pattern.unicodeScalars
            guard remaining.count >= patternScalars.count else { continue }
            if remaining.starts(with: patternScalars) {
                return Match(scalarCount: patternScalars.count)
            }
        }
        return nil
    }

    /// Pattern-match result. `scalarCount` is the number of Unicode
    /// scalars in the matched pattern — the masker advances by this many
    /// scalar indices past the match. (Earlier drafts called this
    /// `utf16Length`, which was misleading: scalar count and UTF-16 code
    /// unit count differ for characters outside the Basic Multilingual
    /// Plane.)
    private struct Match {
        let scalarCount: Int
    }
}

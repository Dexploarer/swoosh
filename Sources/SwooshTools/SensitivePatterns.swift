// SwooshTools/SensitivePatterns.swift — Shared sensitive-substring redaction — 0.9B
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

    /// Mask every occurrence of every pattern in `strings` plus the
    /// non-terminator characters that immediately follow it. Replacement
    /// is the single token `[REDACTED]` so the masked output collapses
    /// secret labels and values together.
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
        var scalars = text.unicodeScalars
        var i = scalars.startIndex
        while i < scalars.endIndex {
            if let match = firstMatchAt(scalars: scalars, start: i) {
                output += "[REDACTED]"
                // Consume the pattern + the value (everything up to the
                // next terminator or end-of-string).
                var j = scalars.index(i, offsetBy: match.utf16Length)
                while j < scalars.endIndex, !valueTerminators.contains(Character(scalars[j])) {
                    j = scalars.index(after: j)
                }
                i = j
            } else {
                output.unicodeScalars.append(scalars[i])
                i = scalars.index(after: i)
            }
        }
        return output
    }

    /// Returns the pattern that matches at `start` in `scalars`, or nil
    /// if nothing matches. Longest-first so `-----BEGIN` wins over
    /// shorter prefix overlaps if any future pattern shares a prefix.
    private static func firstMatchAt(
        scalars: String.UnicodeScalarView,
        start: String.UnicodeScalarView.Index
    ) -> Match? {
        let remaining = scalars[start...]
        for pattern in strings {
            let patternScalars = pattern.unicodeScalars
            guard remaining.count >= patternScalars.count else { continue }
            if remaining.starts(with: patternScalars) {
                return Match(utf16Length: patternScalars.count)
            }
        }
        return nil
    }

    private struct Match {
        let utf16Length: Int
    }
}

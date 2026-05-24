// SwooshPlugins/PluginContentRedactor.swift — Substring redactor for plugin output — 0.9A
//
// Wraps plugin tool output before it enters audit, the model context, or
// the API response. The pattern list is shared with `SwooshMCP`'s redactor
// via `SwooshTools.SensitivePatterns.strings` so new tokens added in one
// place cover the other — the previous design kept byte-identical lists in
// two modules, which was a silent-drift hazard.

import Foundation
import SwooshTools

public struct PluginContentRedactor: Sendable {
    public init() {}

    public func redact(_ text: String) -> String {
        var v = text
        for pattern in SensitivePatterns.strings where v.contains(pattern) {
            v = v.replacingOccurrences(of: pattern, with: "[REDACTED]")
        }
        return v
    }
}

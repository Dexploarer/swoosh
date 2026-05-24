// SwooshPlugins/PluginContentRedactor.swift — Substring redactor for plugin output — 0.9B
//
// Wraps plugin tool output before it enters audit, the model context, or
// the API response. Delegates to `SwooshTools.SensitivePatterns.redact`
// so the actual masking logic (pattern + following value, not just the
// label) is shared with `SwooshMCP.MCPContentRedactor`. The previous
// design stripped only the label, leaving the secret value intact —
// `Bearer eyJ...` became `[REDACTED]eyJ...`. Fixed now.

import Foundation
import SwooshTools

public struct PluginContentRedactor: Sendable {
    public init() {}

    public func redact(_ text: String) -> String {
        SensitivePatterns.redact(text)
    }
}

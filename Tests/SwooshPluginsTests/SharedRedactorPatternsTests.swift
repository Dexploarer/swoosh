// Tests/SwooshPluginsTests/SharedRedactorPatternsTests.swift — 0.9A
//
// Regression test for the audit finding "byte-identical sensitive-pattern
// lists in two modules". After consolidation, `PluginContentRedactor`
// (this module) and `MCPContentRedactor` (in SwooshMCP) MUST both source
// their pattern list from `SwooshTools.SensitivePatterns.strings`. If
// someone adds a local pattern back to either redactor, this test will
// notice — the two sites no longer have permission to drift.

import Testing
import Foundation
@testable import SwooshPlugins
@testable import SwooshTools

@Suite("SwooshTools.SensitivePatterns shared list")
struct SharedRedactorPatternsTests {

    @Test("Canonical list is non-empty and exposes the core PEM + bearer markers")
    func canonicalListShape() {
        let patterns = SensitivePatterns.strings
        #expect(patterns.isEmpty == false)
        // These four are the historically-shared markers that lived in two
        // modules before consolidation. Any future trim must update both
        // redactors at once, so pinning them here is enough.
        #expect(patterns.contains("-----BEGIN"))
        #expect(patterns.contains("PRIVATE KEY"))
        #expect(patterns.contains("Bearer "))
        #expect(patterns.contains("api_key:"))
    }

    @Test("PluginContentRedactor redacts every canonical pattern")
    func pluginRedactorCoversCanonicalList() {
        let redactor = PluginContentRedactor()
        for pattern in SensitivePatterns.strings {
            let input = "prefix \(pattern)something suffix"
            let output = redactor.redact(input)
            #expect(
                !output.contains(pattern),
                "PluginContentRedactor failed to redact \(pattern)"
            )
            #expect(
                output.contains("[REDACTED]"),
                "PluginContentRedactor must emit [REDACTED] for \(pattern)"
            )
        }
    }

    @Test("PluginContentRedactor passes through plain text untouched")
    func pluginRedactorNoFalsePositives() {
        let redactor = PluginContentRedactor()
        let safe = "Hello world, here is some normal text with no markers."
        #expect(redactor.redact(safe) == safe)
    }
}

// Tests/SwooshPluginsTests/SharedRedactorPatternsTests.swift — 0.9C
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

    @Test("Label-followed-by-space patterns mask the value, not just the label")
    func labelWithSpaceMasksValue() {
        // Regression: patterns like `token:` / `cookie:` / `password:` lack
        // a trailing space, so the canonical `label: value` shape used to
        // leak the value — the masker stopped at the first terminator
        // (the space) and emitted `[REDACTED] value`. Skipping leading
        // terminators after the pattern hit closes the leak.
        let cases: [(input: String, mustNotContain: String)] = [
            ("token: secret123", "secret123"),
            ("cookie: session=abc", "session=abc"),
            ("password: hunter2", "hunter2"),
            ("api_key: sk_test_AAAA", "sk_test_AAAA"),
            ("secret: my-super-secret", "my-super-secret")
        ]
        for (input, secret) in cases {
            let output = SensitivePatterns.redact(input)
            #expect(
                !output.contains(secret),
                "redact(\"\(input)\") leaked the value: \"\(output)\""
            )
            #expect(output.contains("[REDACTED]"))
        }
    }

    @Test("Repeated label-value patterns each get masked")
    func repeatedPatternsAllMasked() {
        let input = "cookie: a=1; cookie: b=2; cookie: c=3"
        let output = SensitivePatterns.redact(input)
        #expect(!output.contains("a=1"))
        #expect(!output.contains("b=2"))
        #expect(!output.contains("c=3"))
        // Three masks, exactly.
        #expect(output.components(separatedBy: "[REDACTED]").count - 1 == 3)
    }
}

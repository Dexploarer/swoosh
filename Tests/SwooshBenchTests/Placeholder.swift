// SwooshBenchTests/Placeholder.swift — Scaffolding only
//
// Real benchmark tests will land alongside the SwooshBench module's first
// shipping benchmark. This placeholder keeps the SPM target compilable
// until then.

import Testing

@Suite("SwooshBench placeholder")
struct SwooshBenchPlaceholderTests {
    @Test("Module compiles")
    func compiles() {
        #expect(true)
    }
}

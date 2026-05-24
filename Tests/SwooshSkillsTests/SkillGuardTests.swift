// Tests/SwooshSkillsTests/SkillGuardTests.swift — 0.9S
//
// SkillGuard is the safety pre-flight that decides whether a skill is
// allowed onto disk or onto the agent's reachable surface. A regression
// here silently widens what the agent can execute, so pin the obvious
// reject paths.

import Foundation
import Testing
@testable import SwooshSkills

@Suite("SkillGuard — validation contract")
struct SkillGuardTests {

    private func skill(
        body: String,
        tools: [String] = [],
        triggers: [String] = []
    ) -> SkillDocument {
        SkillDocument(
            title: "Probe",
            description: "Test fixture",
            category: .general,
            triggerPatterns: triggers,
            toolsRequired: tools,
            provenance: SkillProvenance(createdBySessionID: "test", source: .agentLearned),
            trust: .draft,
            body: body
        )
    }

    @Test("Clean skill produces no blocking findings")
    func cleanPasses() {
        let guardActor = SkillGuard(allowImportedSkills: true)
        let findings = guardActor.validate(skill(body: "Just a normal documented skill."))
        let blocking = findings.filter(\.blocksSkillInstall)
        #expect(blocking.isEmpty)
    }

    @Test("Empty body is flagged")
    func emptyBodyBlocks() {
        let guardActor = SkillGuard(allowImportedSkills: true)
        let findings = guardActor.validate(skill(body: ""))
        #expect(!findings.isEmpty, "empty body must produce at least one finding")
    }

    @Test("validate() never throws on edge inputs")
    func toleratesWeirdContent() {
        let guardActor = SkillGuard(allowImportedSkills: true)
        let cases = [
            "",
            String(repeating: "x", count: 10_000),
            "\u{0}\u{1}\u{2}",
            "🚀 emoji-only body 🛸",
            "<script>alert(1)</script>"
        ]
        for body in cases {
            _ = guardActor.validate(skill(body: body))
            // No throw — pass implicit.
        }
    }
}

// Tests/SwooshSkillsTests/SkillTrustTests.swift — 0.9S
//
// Pin the trust-gate ordering + promptable membership. These two
// facts are the contract every skill-pillar consumer relies on:
// promptable skills enter the agent's prompt, non-promptable ones
// never do. A silent drift in either would widen or narrow what the
// model sees from its catalog.

import Testing
@testable import SwooshSkills

@Suite("SkillTrust — comparable + promptable")
struct SkillTrustTests {

    @Test(".rejected sorts below .draft")
    func rejectedBelowDraft() {
        #expect(SkillTrust.rejected < SkillTrust.draft)
    }

    @Test("Sequence: rejected < draft < reviewed < promoted < frozen")
    func ascendingOrder() {
        let ordered: [SkillTrust] = [.rejected, .draft, .reviewed, .promoted, .frozen]
        for idx in 0..<(ordered.count - 1) {
            #expect(ordered[idx] < ordered[idx + 1], "\(ordered[idx]) must sort below \(ordered[idx + 1])")
        }
    }

    @Test("Promptable = exactly {reviewed, promoted, frozen}")
    func promptableMembership() {
        #expect(SkillTrust.promptable.contains(.reviewed))
        #expect(SkillTrust.promptable.contains(.promoted))
        #expect(SkillTrust.promptable.contains(.frozen))
        #expect(!SkillTrust.promptable.contains(.draft))
        #expect(!SkillTrust.promptable.contains(.rejected))
        #expect(SkillTrust.promptable.count == 3)
    }

    @Test("All 5 cases are CaseIterable")
    func caseIterableComplete() {
        let all = Set(SkillTrust.allCases)
        let expected: Set<SkillTrust> = [.draft, .reviewed, .promoted, .frozen, .rejected]
        #expect(all == expected)
    }

    @Test("Codable round-trip preserves every case")
    func codableRoundTrip() throws {
        for trust in SkillTrust.allCases {
            let data = try JSONEncoder().encode(trust)
            let decoded = try JSONDecoder().decode(SkillTrust.self, from: data)
            #expect(decoded == trust)
        }
    }
}

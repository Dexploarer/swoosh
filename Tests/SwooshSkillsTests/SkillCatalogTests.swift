// Tests/SwooshSkillsTests/SkillCatalogTests.swift — 0.9S
//
// `SkillCatalogEntry` is what enters the system prompt's "Available
// Skills" section. Pin the projection: only (id, title, description,
// trust) make it through — body, support files, provenance must stay
// behind to satisfy Level-0 progressive disclosure.

import Foundation
import Testing
@testable import SwooshSkills

@Suite("SkillCatalogEntry — Level-0 projection contract")
struct SkillCatalogTests {

    private func sampleSkill(
        trust: SkillTrust = .promoted
    ) -> SkillDocument {
        SkillDocument(
            title: "Test skill",
            description: "Used by SkillCatalogTests.",
            category: .general,
            triggerPatterns: ["test"],
            provenance: SkillProvenance(createdBySessionID: "test-session", source: .agentLearned),
            tags: ["test"],
            trust: trust,
            body: "## Secret body\nShould not appear in catalog entry."
        )
    }

    @Test("Entry preserves id / title / description / trust")
    func projection() {
        let skill = sampleSkill()
        let entry = SkillCatalogEntry(skill)
        #expect(entry.id == skill.id)
        #expect(entry.title == "Test skill")
        #expect(entry.description == "Used by SkillCatalogTests.")
        #expect(entry.trust == .promoted)
    }

    @Test("Trust value flows through verbatim for every case")
    func trustPropagation() {
        for trust in SkillTrust.allCases {
            let entry = SkillCatalogEntry(sampleSkill(trust: trust))
            #expect(entry.trust == trust)
        }
    }

    @Test("Codable round-trip preserves the entry")
    func codableRoundTrip() throws {
        let entry = SkillCatalogEntry(sampleSkill())
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(SkillCatalogEntry.self, from: data)
        #expect(decoded.id == entry.id)
        #expect(decoded.title == entry.title)
        #expect(decoded.description == entry.description)
        #expect(decoded.trust == entry.trust)
    }
}

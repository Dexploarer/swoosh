// SwooshScoutTests/ScoutPipelineTests.swift — Scout autopilot pipeline tests

import Foundation
import Testing
@testable import SwooshScout

@Suite("Scout Pipeline")
struct ScoutPipelineTests {
    @Test("Autopilot mode skips unavailable permissions without prompting")
    func skipUnavailableDoesNotRequestPermission() async throws {
        let source = PermissionPromptSource()
        let pipeline = ScoutPipeline(sources: [source])

        let result = try await pipeline.run(
            depth: .deep,
            options: ScoutPipelineOptions(permissionMode: .skipUnavailable)
        )

        #expect(result.recordsCollected == 0)
        #expect(source.requestCount == 0)
    }

    @Test("Existing approved or pending memory text suppresses duplicate candidates")
    func existingMemoriesSuppressDuplicateCandidates() async throws {
        let source = StaticSource(records: [
            ScoutRecord(sourceID: "installed_apps", kind: .installedApp, sensitivity: .low, content: "Xcode"),
            ScoutRecord(sourceID: "installed_apps", kind: .installedApp, sensitivity: .low, content: "Docker"),
        ])
        let pipeline = ScoutPipeline(sources: [source])

        let result = try await pipeline.run(
            depth: .minimal,
            options: ScoutPipelineOptions(existingMemories: [
                ExistingMemorySummary(
                    text: "User is a developer. Development tools: Xcode, Docker.",
                    category: "profile"
                ),
            ])
        )

        #expect(result.candidates.isEmpty)
    }

    @Test("Candidate planner keeps the strongest duplicate")
    func plannerKeepsStrongestDuplicate() {
        let candidates = [
            MemoryCandidate(
                text: "User prefers Swift.",
                category: "preference",
                confidence: 0.6,
                sensitivity: .low
            ),
            MemoryCandidate(
                text: "  User prefers   Swift. ",
                category: "preference",
                confidence: 0.9,
                sensitivity: .low
            ),
        ]

        let planned = CandidateReviewPlanner().plan(candidates: candidates, existingMemories: [])

        #expect(planned.count == 1)
        #expect(planned[0].confidence == 0.9)
    }

    @Test("Passive signal source becomes a workflow candidate")
    func passiveSignalsBecomeWorkflowCandidate() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("swoosh-signal-test-\(UUID().uuidString).jsonl")
        let store = PersonalizationSignalStore(url: url)
        defer { try? FileManager.default.removeItem(at: url) }

        try await store.append(PersonalizationSignal(kind: .appFocus, label: "Xcode", weight: 10))
        try await store.append(PersonalizationSignal(kind: .appFocus, label: "Xcode", weight: 8))

        let pipeline = ScoutPipeline(sources: [
            PersonalizationSignalSource(store: store),
        ])

        let result = try await pipeline.run(depth: .minimal)

        #expect(result.recordsCollected == 1)
        #expect(result.candidates.count == 1)
        #expect(result.candidates[0].category == "workflow")
        #expect(result.candidates[0].text.contains("Xcode"))
    }

    @Test("Operational source catalog does not expose empty entitlement scaffolds")
    func operationalCatalogExcludesEmptyScaffolds() {
        let ids = Set(ScoutSourceCatalog.operationalLocalSources().map(\.id))

        #expect(ids.contains("device"))
        #expect(ids.contains("installed_apps"))
        #expect(ids.contains("shell_env"))
        #expect(!ids.contains("music_history"))
        #expect(!ids.contains("screen_time"))
    }
}

private final class PermissionPromptSource: ScoutSource, @unchecked Sendable {
    let id = "prompting"
    let displayName = "Prompting Source"
    let description = "Test source"
    let sensitivity = Sensitivity.low
    let requiredPermissions: [String] = []
    var requestCount = 0

    func checkPermission() async throws -> SourcePermissionStatus { .notDetermined }

    func requestPermission() async throws -> SourcePermissionStatus {
        requestCount += 1
        return .granted
    }

    func scan(progress: ScanProgress) async throws -> [ScoutRecord] {
        [
            ScoutRecord(sourceID: id, kind: .deviceInfo, sensitivity: .low, content: "should not scan"),
        ]
    }
}

private struct StaticSource: ScoutSource {
    let id = "static"
    let displayName = "Static Source"
    let description = "Test source"
    let sensitivity = Sensitivity.low
    let requiredPermissions: [String] = []
    let records: [ScoutRecord]

    func checkPermission() async throws -> SourcePermissionStatus { .granted }
    func requestPermission() async throws -> SourcePermissionStatus { .granted }
    func scan(progress: ScanProgress) async throws -> [ScoutRecord] { records }
}

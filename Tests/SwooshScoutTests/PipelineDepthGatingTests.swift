// Tests/SwooshScoutTests/PipelineDepthGatingTests.swift — 0.9S Depth × Sensitivity gating
//
// `ScoutPipeline.shouldInclude(_:depth:)` is the privacy gate that
// decides which sources even *run* given the user's chosen
// PersonalizationDepth. It's the difference between "swoosh setup"
// scanning installed apps and scanning the user's HealthKit sleep
// data. A regression here either over-shares (high-sensitivity source
// runs at `.minimal`) or under-delivers (`.deep` profile misses a
// `.high` source).
//
// Strategy: define one stub source per Sensitivity tier (low / medium
// / high) and assert the inclusion matrix for each depth.

import Foundation
import Testing
@testable import SwooshScout

private struct StubSource: ScoutSource {
    let id: String
    let displayName: String
    let description = "Stub"
    let sensitivity: Sensitivity
    let requiredPermissions: [String] = []

    func checkPermission() async throws -> SourcePermissionStatus { .granted }
    func requestPermission() async throws -> SourcePermissionStatus { .granted }
    func scan(progress: ScanProgress) async throws -> [ScoutRecord] { [] }
}

private let lowSource = StubSource(id: "low", displayName: "Low", sensitivity: .low)
private let medSource = StubSource(id: "med", displayName: "Med", sensitivity: .medium)
private let highSource = StubSource(id: "high", displayName: "High", sensitivity: .high)
private let criticalSource = StubSource(id: "crit", displayName: "Crit", sensitivity: .critical)

private func includesAt(_ depth: PersonalizationDepth, _ source: any ScoutSource) -> Bool {
    ScoutPipeline(sources: []).shouldInclude(source, depth: depth)
}

@Suite("ScoutPipeline depth × sensitivity gating matrix")
struct PipelineDepthGatingTests {

    @Test(".minimal includes .low only")
    func minimalDepth() {
        #expect(includesAt(.minimal, lowSource))
        #expect(!includesAt(.minimal, medSource))
        #expect(!includesAt(.minimal, highSource))
        #expect(!includesAt(.minimal, criticalSource))
    }

    @Test(".recommended includes .low + .medium")
    func recommendedDepth() {
        #expect(includesAt(.recommended, lowSource))
        #expect(includesAt(.recommended, medSource))
        #expect(!includesAt(.recommended, highSource))
        #expect(!includesAt(.recommended, criticalSource))
    }

    @Test(".deep includes .low + .medium + .high — NOT .critical")
    func deepDepth() {
        #expect(includesAt(.deep, lowSource))
        #expect(includesAt(.deep, medSource))
        #expect(includesAt(.deep, highSource))
        #expect(!includesAt(.deep, criticalSource),
                ".critical is reserved for refused inputs (raw secrets / cookies) — no depth opts in")
    }

    @Test(".custom includes everything the caller passed in (no gate)")
    func customDepth() {
        #expect(includesAt(.custom, lowSource))
        #expect(includesAt(.custom, medSource))
        #expect(includesAt(.custom, highSource))
        #expect(includesAt(.custom, criticalSource))
    }

    @Test(".critical never runs at any non-custom depth — privacy invariant")
    func criticalNeverRunsExceptCustom() {
        for depth in [PersonalizationDepth.minimal, .recommended, .deep] {
            #expect(!includesAt(depth, criticalSource), "\(depth) must not run .critical")
        }
    }
}

@Suite("ScoutPipelineOptions defaults — autopilot safety")
struct ScoutPipelineOptionsDefaultsTests {

    @Test("Default permissionMode is .skipUnavailable — unattended-safe")
    func defaultPermissionModeIsSkipUnavailable() {
        // The default must NOT prompt — any silent default-using caller
        // (autopilot, daemon) would otherwise open OS permission dialogs
        // while unattended.
        let options = ScoutPipelineOptions()
        #expect(options.permissionMode == .skipUnavailable)
    }

    @Test("Default existingMemories is empty")
    func defaultExistingMemoriesIsEmpty() {
        #expect(ScoutPipelineOptions().existingMemories.isEmpty)
    }

    @Test("Default minimumConfidence is 0 (don't drop low-confidence candidates by default)")
    func defaultMinimumConfidence() {
        #expect(ScoutPipelineOptions().minimumConfidence == 0.0)
    }

    @Test("Explicit .requestIfNeeded propagates")
    func explicitRequestIfNeeded() {
        let options = ScoutPipelineOptions(permissionMode: .requestIfNeeded)
        #expect(options.permissionMode == .requestIfNeeded)
    }
}


// SwooshScout/Pipeline.swift — 0.9S End-to-end Scout → Redact → Store → Candidates pipeline
//
// Holds the pipeline types + run-loop only. The per-RecordKind candidate
// generators + canonical app-name sets + setup-report builder live in
// `Pipeline+CandidateGenerators.swift` so each file stays under the
// project's 400 LOC ceiling and the orchestration code is easy to scan.

import Foundation

// MARK: - Pipeline runner

public struct ScoutPipelineResult: Sendable {
    public let sourcesScanned: Int
    public let recordsCollected: Int
    public let recordsRedacted: Int
    public let candidatesGenerated: Int
    public let setupReport: String
    public let records: [ScoutRecord]
    public let candidates: [MemoryCandidate]
}

public enum ScoutPermissionMode: Sendable, Equatable {
    /// Synchronously call `requestPermission()` on any source whose
    /// `checkPermission()` came back non-`.granted`. Suitable for
    /// foreground user-attended flows (e.g. `swoosh setup` in a TTY).
    case requestIfNeeded
    /// Skip any source that isn't already `.granted`. The autopilot in
    /// `swooshd` uses this so unattended personalization never opens
    /// OS permission prompts.
    case skipUnavailable
}

public struct ExistingMemorySummary: Sendable {
    public let text: String
    public let category: String

    public init(text: String, category: String) {
        self.text = text
        self.category = category
    }
}

public struct ScoutPipelineOptions: Sendable {
    public let permissionMode: ScoutPermissionMode
    public let existingMemories: [ExistingMemorySummary]
    public let minimumConfidence: Double

    /// Default mode is `.skipUnavailable` — the unattended-safe choice
    /// (no OS permission prompts will appear). Foreground callers that
    /// genuinely want to prompt the user pass `.requestIfNeeded`
    /// explicitly. This default protects autopilot callers that omit
    /// the parameter from silently breaking the "never prompt while
    /// unattended" invariant documented in the module CLAUDE.md.
    public init(
        permissionMode: ScoutPermissionMode = .skipUnavailable,
        existingMemories: [ExistingMemorySummary] = [],
        minimumConfidence: Double = 0.0
    ) {
        self.permissionMode = permissionMode
        self.existingMemories = existingMemories
        self.minimumConfidence = minimumConfidence
    }
}

public struct ScoutPipeline: Sendable {
    let sources: [any ScoutSource]
    let redactor: SecretRedactor

    public init(sources: [any ScoutSource]) {
        self.sources = sources
        self.redactor = SecretRedactor()
    }

    /// Run the full pipeline: scan → redact → generate candidates → produce report
    /// `progress` is called before each source scan with `(current, total, sourceName)`.
    public func run(
        depth: PersonalizationDepth,
        options: ScoutPipelineOptions = ScoutPipelineOptions(),
        log: @Sendable (String) -> Void = { _ in },
        progress: @Sendable (_ current: Int, _ total: Int, _ sourceName: String) -> Void = { _, _, _ in }
    ) async throws -> ScoutPipelineResult {
        let scanProgress = ScanProgress()
        var allRecords: [ScoutRecord] = []
        var sourcesScanned = 0
        var totalRedacted = 0
        let applicableSources = sources.filter { shouldInclude($0, depth: depth) }
        let totalApplicable = applicableSources.count

        // Phase 1: Scan each source
        for (index, source) in applicableSources.enumerated() {
            progress(index + 1, totalApplicable, source.displayName)

            let permStatus = try await source.checkPermission()
            var hasPermission = (permStatus == .granted)

            if !hasPermission {
                switch options.permissionMode {
                case .requestIfNeeded:
                    log("  ⟳ Requesting permission for \(source.displayName)...")
                    let requested = try await source.requestPermission()
                    hasPermission = (requested == .granted)
                case .skipUnavailable:
                    log("  ○ \(source.displayName) — skipped (permission unavailable)")
                }
            }

            guard hasPermission else {
                if options.permissionMode == .requestIfNeeded {
                    log("  ✗ \(source.displayName) — permission denied")
                }
                continue
            }

            log("  ⟳ Scanning \(source.displayName)...")
            let records = try await source.scan(progress: scanProgress)
            sourcesScanned += 1
            log("  ✓ \(source.displayName) — \(records.count) records")

            allRecords.append(contentsOf: records)
        }

        // Phase 2: Redact
        let redactedRecords = allRecords.map { record -> ScoutRecord in
            let redacted = redactor.redact(record)
            if redacted.content != record.content { totalRedacted += 1 }
            return redacted
        }

        if totalRedacted > 0 {
            log("  ⚠ Redacted \(totalRedacted) records containing potential secrets")
        }

        // Phase 3: Generate memory candidates
        let candidates = CandidateReviewPlanner().plan(
            candidates: generateCandidates(from: redactedRecords),
            existingMemories: options.existingMemories,
            minimumConfidence: options.minimumConfidence
        )
        log("  ✓ Generated \(candidates.count) memory candidates")

        // Phase 4: Produce setup report
        let report = generateReport(records: redactedRecords, candidates: candidates)

        return ScoutPipelineResult(
            sourcesScanned: sourcesScanned,
            recordsCollected: allRecords.count,
            recordsRedacted: totalRedacted,
            candidatesGenerated: candidates.count,
            setupReport: report,
            records: redactedRecords,
            candidates: candidates
        )
    }

    /// Depth → max-sensitivity gate. `.minimal` keeps only `.low`,
    /// `.recommended` adds `.medium`, `.deep` adds `.high`, `.custom`
    /// trusts the caller's source list verbatim. The `.critical` tier
    /// is never scanned by any depth — those sources are reserved for
    /// data we explicitly refuse to ingest (raw secrets / cookies).
    func shouldInclude(_ source: any ScoutSource, depth: PersonalizationDepth) -> Bool {
        switch depth {
        case .minimal:    return source.sensitivity <= .low
        case .recommended: return source.sensitivity <= .medium
        case .deep:       return source.sensitivity <= .high
        case .custom:     return true
        }
    }
}

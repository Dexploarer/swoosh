// SwooshManifesting/Manifester.swift — The self-improvement loop runner — 0.1A
//
// One actor, one method (`runOnce`), one explicit pipeline. The phases
// are wired up here; model-backed pattern mining is injected as a closure
// so this module stays free of model-provider deps. The built-in miner is
// deterministic and produces conservative observations from the audit window.
//
// Every pass writes one Manifestation record. That record is the
// replayable, auditable, user-reviewable evidence of what the agent
// thought about during downtime.

import Foundation

/// A typed handle the manifester uses to read from the audit log.
/// Implementations pull from ActantDB (production) or an in-memory
/// list (tests). Kept opaque so this module doesn't depend on
/// SwooshCore's audit types.
public protocol ManifestationAuditSource: Sendable {
    func eventsSince(_ cursor: Date?) async throws -> [ManifestationAuditEvent]
}

/// Lightweight projection of an audit event — just enough for the
/// mining phase to reason about. Real audit records (e.g.,
/// `ResponseAuditRecord`) are projected into this shape by the source.
public struct ManifestationAuditEvent: Codable, Sendable, Identifiable {
    public let id: String
    public let kind: String             // "tool_call", "user_correction", "session_start", ...
    public let sessionID: String?
    public let toolName: String?
    public let summary: String          // Short, redaction-safe description
    public let timestamp: Date

    public init(
        id: String,
        kind: String,
        sessionID: String? = nil,
        toolName: String? = nil,
        summary: String,
        timestamp: Date
    ) {
        self.id = id
        self.kind = kind
        self.sessionID = sessionID
        self.toolName = toolName
        self.summary = summary
        self.timestamp = timestamp
    }
}

/// Empty source — produces no events when the caller has no audit reader.
public struct EmptyManifestationAuditSource: ManifestationAuditSource {
    public init() {}
    public func eventsSince(_ cursor: Date?) async throws -> [ManifestationAuditEvent] { [] }
}

/// The self-improvement loop itself.
public actor Manifester {
    public typealias PatternMiner = @Sendable (
        [ManifestationAuditEvent]
    ) async throws -> [ManifestationProposal]

    private let store: any ManifestationStoring
    private let auditSource: any ManifestationAuditSource
    private let miner: PatternMiner

    public init(
        store: any ManifestationStoring,
        auditSource: any ManifestationAuditSource = EmptyManifestationAuditSource(),
        miner: @escaping PatternMiner = Manifester.deterministicMiner
    ) {
        self.store = store
        self.auditSource = auditSource
        self.miner = miner
    }

    /// Run one manifestation pass. Persists the resulting record (with
    /// proposals and summary) and returns it. Safe to call concurrently
    /// with chat activity — the manifester only reads from the audit
    /// stream and writes to its own store.
    @discardableResult
    public func runOnce(triggerReason: String = "manual") async throws -> Manifestation {
        var manifestation = Manifestation(triggerReason: triggerReason)
        try await store.save(manifestation)

        // ── Gather ─────────────────────────────────────────────────
        let lastCompleted = try await store.mostRecentCompleted()
        manifestation.auditWindowStart = lastCompleted?.finishedAt
        var gatherPhase = ManifestationPhase(name: .gather)
        let events: [ManifestationAuditEvent]
        do {
            events = try await auditSource.eventsSince(manifestation.auditWindowStart)
            gatherPhase.observation = "gathered \(events.count) events"
        } catch {
            gatherPhase.observation = "gather failed: \(error.localizedDescription)"
            return try await complete(&manifestation, with: [gatherPhase], status: .failed)
        }
        gatherPhase.finishedAt = Date()
        manifestation.auditWindowEnd = events.last?.timestamp ?? manifestation.startedAt

        // Short-circuit when nothing new has happened. No phantom proposals.
        if events.isEmpty {
            return try await complete(
                &manifestation,
                with: [gatherPhase],
                status: .skipped,
                summary: "No new audit events since last manifestation."
            )
        }

        // ── Mine ───────────────────────────────────────────────────
        var minePhase = ManifestationPhase(name: .mine)
        let proposals: [ManifestationProposal]
        do {
            proposals = try await miner(events)
            minePhase.observation = "mined \(proposals.count) proposals"
        } catch {
            minePhase.observation = "mine failed: \(error.localizedDescription)"
            return try await complete(
                &manifestation,
                with: [gatherPhase, minePhase],
                status: .failed
            )
        }
        minePhase.finishedAt = Date()

        // ── Propose ────────────────────────────────────────────────
        // The proposals already exist as values; "proposing" here means
        // committing them to this manifestation's record. Writing them
        // to the *skill / memory* stores is a downstream step the
        // reviewer triggers — never auto-promoted.
        var proposePhase = ManifestationPhase(name: .propose)
        manifestation.proposals = proposals
        proposePhase.observation = "recorded \(proposals.count) proposals (none auto-applied)"
        proposePhase.finishedAt = Date()

        // ── Consolidate ────────────────────────────────────────────
        var consolidatePhase = ManifestationPhase(name: .consolidate)
        let merges = consolidate(proposals: proposals)
        manifestation.proposals.append(contentsOf: merges)
        consolidatePhase.observation = "added \(merges.count) merge suggestions"
        consolidatePhase.finishedAt = Date()

        // ── Summarize ──────────────────────────────────────────────
        var summarizePhase = ManifestationPhase(name: .summarize)
        let summary = summarize(events: events, proposals: manifestation.proposals)
        manifestation.summary = summary
        summarizePhase.observation = "summary written (\(summary.count) chars)"
        summarizePhase.finishedAt = Date()

        return try await complete(
            &manifestation,
            with: [gatherPhase, minePhase, proposePhase, consolidatePhase, summarizePhase],
            status: .completed
        )
    }

    // MARK: - Consolidation + summary (deterministic, no model calls)

    /// Find proposals that look like duplicates by title and emit a
    /// `skillMerge` suggestion. Deterministic; runs without a model.
    private func consolidate(proposals: [ManifestationProposal]) -> [ManifestationProposal] {
        let skillProposals = proposals.filter { $0.kind == .newSkill }
        let grouped = Dictionary(grouping: skillProposals) { $0.title.lowercased() }
        return grouped
            .filter { $0.value.count > 1 }
            .map { (title, dupes) in
                ManifestationProposal(
                    kind: .skillMerge,
                    title: "Merge candidates titled \"\(title)\"",
                    rationale: "Saw \(dupes.count) proposed skills with the same title in this pass.",
                    confidence: 0.7,
                    payloadJSON: "{\"candidateIDs\":[" +
                        dupes.map { "\"\($0.id)\"" }.joined(separator: ",") + "]}"
                )
            }
    }

    private func summarize(
        events: [ManifestationAuditEvent],
        proposals: [ManifestationProposal]
    ) -> String {
        var lines: [String] = []
        lines.append("Manifestation pass — \(events.count) audit events, \(proposals.count) proposals.")
        let byKind = Dictionary(grouping: proposals, by: \.kind)
        for kind in ManifestationProposal.Kind.allCases {
            if let items = byKind[kind], !items.isEmpty {
                lines.append("- \(kind.rawValue): \(items.count)")
            }
        }
        return lines.joined(separator: "\n")
    }

    private func complete(
        _ manifestation: inout Manifestation,
        with phases: [ManifestationPhase],
        status: ManifestationStatus,
        summary: String? = nil
    ) async throws -> Manifestation {
        manifestation.phases = phases
        manifestation.status = status
        manifestation.finishedAt = Date()
        if let summary { manifestation.summary = summary }
        try await store.update(manifestation)
        return manifestation
    }

    // MARK: - Built-in miner

    public static let deterministicMiner: PatternMiner = { events in
        let byKind = Dictionary(grouping: events, by: \.kind)
        let kindProposals = byKind
            .filter { $0.value.count >= 3 }
            .map { kind, matches in
                ManifestationProposal(
                    kind: .observation,
                    title: "Repeated \(kind) activity",
                    rationale: "Saw \(matches.count) audit events of kind \(kind) in this window.",
                    confidence: min(0.95, 0.5 + Double(matches.count) / 20.0),
                    payloadJSON: "{\"eventKind\":\"\(kind)\",\"count\":\(matches.count)}"
                )
            }

        let byTool = Dictionary(grouping: events.compactMap { event -> (String, ManifestationAuditEvent)? in
            guard let toolName = event.toolName else { return nil }
            return (toolName, event)
        }, by: \.0)
        let toolProposals = byTool
            .filter { $0.value.count >= 2 }
            .map { toolName, matches in
                ManifestationProposal(
                    kind: .observation,
                    title: "Repeated \(toolName) tool use",
                    rationale: "Saw \(matches.count) uses of \(toolName); this may be worth turning into a skill if the pattern repeats.",
                    confidence: min(0.9, 0.45 + Double(matches.count) / 20.0),
                    payloadJSON: "{\"toolName\":\"\(toolName)\",\"count\":\(matches.count)}"
                )
            }

        return Array((kindProposals + toolProposals).prefix(5))
    }
}

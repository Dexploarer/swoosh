// SwooshWorkers/WorkerScheduler.swift — 0.7B Worker Scheduler + Runner

import Foundation
import SwooshTools

// ═══════════════════════════════════════════════════════════════════
// MARK: - Worker errors
// ═══════════════════════════════════════════════════════════════════

public enum WorkerError: Error, Sendable {
    case laneNotFound(String)
    case laneDisabled(String)
    case laneAtCapacity(String)
    case assignmentNotFound(String)
    case runNotFound(String)
    case cardNotAssigned(String)
    case budgetExceeded(String)
    case timedOut(String)
    case alreadyRunning(String)
    case invalidAssignmentStatus(String)
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Worker scheduler
// ═══════════════════════════════════════════════════════════════════

public actor WorkerScheduler {
    private let store: any WorkerStoring
    private let redactor: WorkerContentRedactor

    public init(store: any WorkerStoring, redactor: WorkerContentRedactor = WorkerContentRedactor()) {
        self.store = store; self.redactor = redactor
    }

    // ── Assignment ────────────────────────────────────────────────

    public func assign(cardID: String, laneID: String, assignedBy: String = "human") async throws -> WorkerAssignment {
        guard let lane = try await store.getLane(id: laneID) else {
            throw WorkerError.laneNotFound(laneID)
        }
        guard lane.enabled else { throw WorkerError.laneDisabled(laneID) }

        let assignment = WorkerAssignment(cardID: cardID, laneID: laneID, assignedBy: assignedBy)
        try await store.saveAssignment(assignment)
        return assignment
    }

    // ── Start run ─────────────────────────────────────────────────

    public func startRun(assignmentID: String) async throws -> WorkerRun {
        guard var assignment = try await store.getAssignment(id: assignmentID) else {
            throw WorkerError.assignmentNotFound(assignmentID)
        }
        guard assignment.status == .assigned || assignment.status == .claimed else {
            throw WorkerError.invalidAssignmentStatus(assignment.status.rawValue)
        }

        guard let lane = try await store.getLane(id: assignment.laneID) else {
            throw WorkerError.laneNotFound(assignment.laneID)
        }
        guard lane.enabled else { throw WorkerError.laneDisabled(lane.id) }

        // Check capacity
        let activeRuns = try await store.listRuns(cardID: nil, laneID: lane.id)
            .filter { $0.status == .running || $0.status == .pausedForApproval }
        guard activeRuns.count < lane.maxConcurrentRuns else {
            throw WorkerError.laneAtCapacity(lane.id)
        }

        let run = WorkerRun(
            assignmentID: assignmentID, cardID: assignment.cardID,
            laneID: lane.id, sessionID: UUID().uuidString, budget: lane.budget
        )
        try await store.saveRun(run)

        assignment.status = .running; assignment.updatedAt = Date()
        try await store.updateAssignment(assignment)

        return run
    }

    // ── Record heartbeat ──────────────────────────────────────────

    public func recordHeartbeat(runID: String, message: String?) async throws {
        guard var run = try await store.getRun(id: runID) else {
            throw WorkerError.runNotFound(runID)
        }
        run.heartbeatAt = Date()
        try await store.updateRun(run)

        let hb = WorkerHeartbeat(
            runID: runID, cardID: run.cardID, status: run.status,
            message: message.map { redactor.redact($0) },
            toolCallCount: run.toolCallCount, turnCount: run.turnCount
        )
        try await store.saveHeartbeat(hb)
    }

    // ── Record log ────────────────────────────────────────────────

    public func recordLog(runID: String, level: WorkerLogLevel, message: String) async throws {
        let log = WorkerLog(runID: runID, level: level, message: redactor.redact(message))
        try await store.saveLog(log)
    }

    // ── Record tool call ──────────────────────────────────────────

    public func recordToolCall(runID: String) async throws {
        guard var run = try await store.getRun(id: runID) else {
            throw WorkerError.runNotFound(runID)
        }
        run.toolCallCount += 1
        if run.isBudgetExceeded {
            run.status = .budgetExceeded; run.completedAt = Date()
        }
        try await store.updateRun(run)
    }

    // ── Record turn ───────────────────────────────────────────────

    public func recordTurn(runID: String) async throws {
        guard var run = try await store.getRun(id: runID) else {
            throw WorkerError.runNotFound(runID)
        }
        run.turnCount += 1
        if run.isBudgetExceeded {
            run.status = .budgetExceeded; run.completedAt = Date()
        }
        if run.isTimedOut {
            run.status = .timedOut; run.completedAt = Date()
        }
        try await store.updateRun(run)
    }

    // ── Complete ──────────────────────────────────────────────────

    public func complete(runID: String, summary: String, recommendations: [String] = [], artifactIDs: [String] = []) async throws -> WorkerResult {
        guard var run = try await store.getRun(id: runID) else {
            throw WorkerError.runNotFound(runID)
        }
        run.status = .completed; run.completedAt = Date()

        let result = WorkerResult(
            runID: runID, cardID: run.cardID, status: .completed,
            summary: redactor.redact(summary), recommendations: recommendations,
            artifactIDs: artifactIDs
        )
        run.resultID = result.id
        try await store.updateRun(run)
        try await store.saveResult(result)

        // Update assignment
        if var assignment = try await store.getAssignment(id: run.assignmentID) {
            assignment.status = .completed; assignment.updatedAt = Date()
            try await store.updateAssignment(assignment)
        }

        return result
    }

    // ── Escalate ──────────────────────────────────────────────────

    public func escalate(runID: String, reason: WorkerEscalationReason, message: String, suggestedAction: String? = nil) async throws -> WorkerEscalation {
        guard var run = try await store.getRun(id: runID) else {
            throw WorkerError.runNotFound(runID)
        }
        run.status = .blocked; run.completedAt = Date()
        try await store.updateRun(run)

        let esc = WorkerEscalation(
            runID: runID, cardID: run.cardID, reason: reason,
            message: redactor.redact(message), suggestedHumanAction: suggestedAction
        )
        try await store.saveEscalation(esc)

        if var assignment = try await store.getAssignment(id: run.assignmentID) {
            assignment.status = .blocked; assignment.updatedAt = Date()
            try await store.updateAssignment(assignment)
        }

        return esc
    }

    // ── Cancel ────────────────────────────────────────────────────

    public func cancel(runID: String) async throws {
        guard var run = try await store.getRun(id: runID) else {
            throw WorkerError.runNotFound(runID)
        }
        run.status = .cancelled; run.completedAt = Date()
        try await store.updateRun(run)

        if var assignment = try await store.getAssignment(id: run.assignmentID) {
            assignment.status = .cancelled; assignment.updatedAt = Date()
            try await store.updateAssignment(assignment)
        }
    }

    // ── Queries ───────────────────────────────────────────────────

    public func getRun(_ id: String) async throws -> WorkerRun? { try await store.getRun(id: id) }
    public func getAssignment(_ id: String) async throws -> WorkerAssignment? { try await store.getAssignment(id: id) }
    public func listLanes() async throws -> [WorkerLane] { try await store.listLanes() }
    public func listRuns(cardID: String? = nil, laneID: String? = nil) async throws -> [WorkerRun] { try await store.listRuns(cardID: cardID, laneID: laneID) }
    public func listHeartbeats(runID: String) async throws -> [WorkerHeartbeat] { try await store.listHeartbeats(runID: runID) }
    public func listLogs(runID: String) async throws -> [WorkerLog] { try await store.listLogs(runID: runID) }
    public func listArtifacts(runID: String) async throws -> [WorkerArtifact] { try await store.listArtifacts(runID: runID) }
    public func getResult(_ id: String) async throws -> WorkerResult? { try await store.getResult(id: id) }

    // ── /why ──────────────────────────────────────────────────────

    public func whyExplanation(runID: String) async throws -> String {
        guard let run = try await store.getRun(id: runID) else { return "Worker run not found." }
        let lane = try await store.getLane(id: run.laneID)
        var lines: [String] = []
        lines.append("Worker Run: \(run.id)")
        lines.append("Card: \(run.cardID)")
        lines.append("Lane: \(lane?.name ?? run.laneID)")
        lines.append("Status: \(run.status.rawValue)")
        lines.append("Tools used: \(run.toolCallCount)")
        lines.append("Turns: \(run.turnCount)")
        if let lane = lane {
            if !lane.toolPolicy.deniedTools.isEmpty {
                lines.append("Denied tools: \(lane.toolPolicy.deniedTools.joined(separator: ", "))")
            }
            lines.append("Worker cannot approve gates or resolve approvals.")
            lines.append("Worker cannot expand permissions or spawn other workers.")
        }
        if let result = run.resultID.flatMap({ id in nil as WorkerResult? }) {
            // Result fetched separately
        } else {
            let escalations = try await store.listEscalations(runID: runID)
            if let esc = escalations.first {
                lines.append("Escalation: \(esc.reason.rawValue) — \(esc.message)")
            }
        }
        return lines.joined(separator: "\n")
    }
}

// SwooshWorkers/WorkerStore.swift — 0.7B Worker Store

import Foundation
import SwooshTools

// ═══════════════════════════════════════════════════════════════════
// MARK: - Worker store protocol
// ═══════════════════════════════════════════════════════════════════

public protocol WorkerStoring: Sendable {
    func saveLane(_ lane: WorkerLane) async throws
    func updateLane(_ lane: WorkerLane) async throws
    func getLane(id: String) async throws -> WorkerLane?
    func listLanes() async throws -> [WorkerLane]

    func saveAssignment(_ assignment: WorkerAssignment) async throws
    func updateAssignment(_ assignment: WorkerAssignment) async throws
    func getAssignment(id: String) async throws -> WorkerAssignment?
    func listAssignments(cardID: String?) async throws -> [WorkerAssignment]

    func saveRun(_ run: WorkerRun) async throws
    func updateRun(_ run: WorkerRun) async throws
    func getRun(id: String) async throws -> WorkerRun?
    func listRuns(cardID: String?, laneID: String?) async throws -> [WorkerRun]

    func saveHeartbeat(_ heartbeat: WorkerHeartbeat) async throws
    func listHeartbeats(runID: String) async throws -> [WorkerHeartbeat]

    func saveLog(_ log: WorkerLog) async throws
    func listLogs(runID: String) async throws -> [WorkerLog]

    func saveArtifact(_ artifact: WorkerArtifact) async throws
    func listArtifacts(runID: String) async throws -> [WorkerArtifact]

    func saveResult(_ result: WorkerResult) async throws
    func getResult(id: String) async throws -> WorkerResult?

    func saveEscalation(_ escalation: WorkerEscalation) async throws
    func listEscalations(runID: String) async throws -> [WorkerEscalation]
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - In-memory worker store
// ═══════════════════════════════════════════════════════════════════

public actor InMemoryWorkerStore: WorkerStoring {
    private var lanes: [String: WorkerLane] = [:]
    private var assignments: [String: WorkerAssignment] = [:]
    private var runs: [String: WorkerRun] = [:]
    private var heartbeats: [String: WorkerHeartbeat] = [:]
    private var logs: [String: WorkerLog] = [:]
    private var artifacts: [String: WorkerArtifact] = [:]
    private var results: [String: WorkerResult] = [:]
    private var escalations: [String: WorkerEscalation] = [:]

    public init() {}

    // Lane
    public func saveLane(_ l: WorkerLane) { lanes[l.id] = l }
    public func updateLane(_ l: WorkerLane) { lanes[l.id] = l }
    public func getLane(id: String) -> WorkerLane? { lanes[id] }
    public func listLanes() -> [WorkerLane] { Array(lanes.values).sorted { $0.name < $1.name } }

    // Assignment
    public func saveAssignment(_ a: WorkerAssignment) { assignments[a.id] = a }
    public func updateAssignment(_ a: WorkerAssignment) { assignments[a.id] = a }
    public func getAssignment(id: String) -> WorkerAssignment? { assignments[id] }
    public func listAssignments(cardID: String?) -> [WorkerAssignment] {
        var r = Array(assignments.values)
        if let c = cardID { r = r.filter { $0.cardID == c } }
        return r.sorted { $0.createdAt > $1.createdAt }
    }

    // Run
    public func saveRun(_ run: WorkerRun) { runs[run.id] = run }
    public func updateRun(_ run: WorkerRun) { runs[run.id] = run }
    public func getRun(id: String) -> WorkerRun? { runs[id] }
    public func listRuns(cardID: String?, laneID: String?) -> [WorkerRun] {
        var r = Array(runs.values)
        if let c = cardID { r = r.filter { $0.cardID == c } }
        if let l = laneID { r = r.filter { $0.laneID == l } }
        return r.sorted { $0.startedAt > $1.startedAt }
    }

    // Heartbeat
    public func saveHeartbeat(_ h: WorkerHeartbeat) { heartbeats[h.id] = h }
    public func listHeartbeats(runID: String) -> [WorkerHeartbeat] {
        heartbeats.values.filter { $0.runID == runID }.sorted { $0.createdAt > $1.createdAt }
    }

    // Log
    public func saveLog(_ l: WorkerLog) { logs[l.id] = l }
    public func listLogs(runID: String) -> [WorkerLog] {
        logs.values.filter { $0.runID == runID }.sorted { $0.createdAt > $1.createdAt }
    }

    // Artifact
    public func saveArtifact(_ a: WorkerArtifact) { artifacts[a.id] = a }
    public func listArtifacts(runID: String) -> [WorkerArtifact] {
        artifacts.values.filter { $0.runID == runID }.sorted { $0.createdAt > $1.createdAt }
    }

    // Result
    public func saveResult(_ r: WorkerResult) { results[r.id] = r }
    public func getResult(id: String) -> WorkerResult? { results[id] }

    // Escalation
    public func saveEscalation(_ e: WorkerEscalation) { escalations[e.id] = e }
    public func listEscalations(runID: String) -> [WorkerEscalation] {
        escalations.values.filter { $0.runID == runID }.sorted { $0.createdAt > $1.createdAt }
    }
}

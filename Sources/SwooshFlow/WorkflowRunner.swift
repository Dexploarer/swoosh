// SwooshFlow/WorkflowRunner.swift — 0.6B Background Runner
//
// Queues and executes triggered workflow runs.
// Uses WorkflowExecutionEngine — never bypasses Firewall.
// Read-only steps run unattended. Risky steps pause for approval.

import Foundation
import SwooshTools

// ═══════════════════════════════════════════════════════════════════
// MARK: - Run request
// ═══════════════════════════════════════════════════════════════════

public struct WorkflowRunRequest06B: Codable, Sendable, Identifiable {
    public let id: String
    public let workflowID: String
    public let triggerID: String?
    public let triggerEventID: String?
    public let origin: WorkflowRunOrigin
    public let providedInputs: [String: JSONValue]
    public let requestedAt: Date

    public init(
        id: String = UUID().uuidString, workflowID: String,
        triggerID: String? = nil, triggerEventID: String? = nil,
        origin: WorkflowRunOrigin = .manual,
        providedInputs: [String: JSONValue] = [:],
        requestedAt: Date = Date()
    ) {
        self.id = id; self.workflowID = workflowID; self.triggerID = triggerID
        self.triggerEventID = triggerEventID; self.origin = origin
        self.providedInputs = providedInputs; self.requestedAt = requestedAt
    }
}

public enum WorkflowRunOrigin: String, Codable, Sendable {
    case manual, schedule, fileChanged, webhook, appEvent, calendarEvent
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Runner policy
// ═══════════════════════════════════════════════════════════════════

public struct WorkflowRunnerPolicy: Codable, Sendable {
    public let allowBackgroundRuns: Bool
    public let allowReadOnlyUnattended: Bool
    public let allowRiskyUnattended: Bool
    public let allowCriticalSteps: Bool
    public let allowSigningOrBroadcasting: Bool
    public let allowGitPush: Bool
    public let allowFileDelete: Bool
    public let maxConcurrentRuns: Int
    public let maxRunsPerWorkflowPerDay: Int
    public let maxRunsPerTriggerPerHour: Int

    public static let safeBackground = WorkflowRunnerPolicy(
        allowBackgroundRuns: true, allowReadOnlyUnattended: true,
        allowRiskyUnattended: false, allowCriticalSteps: false,
        allowSigningOrBroadcasting: false, allowGitPush: false,
        allowFileDelete: false, maxConcurrentRuns: 2,
        maxRunsPerWorkflowPerDay: 12, maxRunsPerTriggerPerHour: 6
    )

    public init(
        allowBackgroundRuns: Bool, allowReadOnlyUnattended: Bool,
        allowRiskyUnattended: Bool, allowCriticalSteps: Bool,
        allowSigningOrBroadcasting: Bool, allowGitPush: Bool,
        allowFileDelete: Bool, maxConcurrentRuns: Int,
        maxRunsPerWorkflowPerDay: Int, maxRunsPerTriggerPerHour: Int
    ) {
        self.allowBackgroundRuns = allowBackgroundRuns; self.allowReadOnlyUnattended = allowReadOnlyUnattended
        self.allowRiskyUnattended = allowRiskyUnattended; self.allowCriticalSteps = allowCriticalSteps
        self.allowSigningOrBroadcasting = allowSigningOrBroadcasting; self.allowGitPush = allowGitPush
        self.allowFileDelete = allowFileDelete; self.maxConcurrentRuns = maxConcurrentRuns
        self.maxRunsPerWorkflowPerDay = maxRunsPerWorkflowPerDay; self.maxRunsPerTriggerPerHour = maxRunsPerTriggerPerHour
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Run queue
// ═══════════════════════════════════════════════════════════════════

public actor WorkflowRunQueue {
    private var queue: [WorkflowRunRequest06B] = []
    public init() {}

    public func enqueue(_ req: WorkflowRunRequest06B) { queue.append(req) }
    public func dequeue() -> WorkflowRunRequest06B? {
        guard !queue.isEmpty else { return nil }
        return queue.removeFirst()
    }
    public func peek() -> WorkflowRunRequest06B? { queue.first }
    public func count() -> Int { queue.count }
    public func listPending() -> [WorkflowRunRequest06B] { queue }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Runner status
// ═══════════════════════════════════════════════════════════════════

public struct WorkflowRunnerStatus: Codable, Sendable {
    public let isRunning: Bool
    public let isPaused: Bool
    public let activeRunCount: Int
    public let queuedRunCount: Int
    public let armedTriggerCount: Int
    public let totalRunsCompleted: Int
    public let lastTickAt: Date?

    public init(isRunning: Bool, isPaused: Bool, activeRunCount: Int,
                queuedRunCount: Int, armedTriggerCount: Int,
                totalRunsCompleted: Int = 0, lastTickAt: Date? = nil) {
        self.isRunning = isRunning; self.isPaused = isPaused
        self.activeRunCount = activeRunCount; self.queuedRunCount = queuedRunCount
        self.armedTriggerCount = armedTriggerCount; self.totalRunsCompleted = totalRunsCompleted
        self.lastTickAt = lastTickAt
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Workflow runner
// ═══════════════════════════════════════════════════════════════════

public actor WorkflowRunner {
    private let queue: WorkflowRunQueue
    private let executionEngine: WorkflowExecutionEngine
    private let policy: WorkflowRunnerPolicy
    private var activeRunIDs: Set<String> = []
    public private(set) var isPaused: Bool = false
    public private(set) var isRunning: Bool = false
    public private(set) var totalCompleted: Int = 0
    public private(set) var lastTickAt: Date?

    public init(queue: WorkflowRunQueue, executionEngine: WorkflowExecutionEngine,
                policy: WorkflowRunnerPolicy = .safeBackground) {
        self.queue = queue; self.executionEngine = executionEngine; self.policy = policy
    }

    public func start() { isRunning = true; isPaused = false }
    public func pause() { isPaused = true }
    public func resume() { isPaused = false }
    public func stop() { isRunning = false }

    /// Process one run from the queue. Call this on a tick interval.
    public func tick() async -> WorkflowExecutionReport? {
        lastTickAt = Date()
        guard isRunning && !isPaused else { return nil }
        guard activeRunIDs.count < policy.maxConcurrentRuns else { return nil }
        guard let request = await queue.dequeue() else { return nil }

        activeRunIDs.insert(request.id)
        defer { activeRunIDs.remove(request.id) }

        do {
            let report = try await executionEngine.start(
                WorkflowExecutionRequest(
                    draftID: request.workflowID,
                    providedInputs: request.providedInputs,
                    mode: .manualApprovalGated,
                    scope: .allSteps
                )
            )
            totalCompleted += 1
            return report
        } catch {
            return nil
        }
    }

    public func status() async -> WorkflowRunnerStatus {
        WorkflowRunnerStatus(
            isRunning: isRunning, isPaused: isPaused,
            activeRunCount: activeRunIDs.count,
            queuedRunCount: await queue.count(),
            armedTriggerCount: 0,
            totalRunsCompleted: totalCompleted,
            lastTickAt: lastTickAt
        )
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Webhook safety
// ═══════════════════════════════════════════════════════════════════

public struct LocalWebhookServerConfig: Codable, Sendable {
    public let bindHost: String  // must be 127.0.0.1
    public let port: Int
    public let maxBodyBytes: Int

    public init(bindHost: String = "127.0.0.1", port: Int = 8787, maxBodyBytes: Int = 65536) {
        self.bindHost = bindHost; self.port = port; self.maxBodyBytes = maxBodyBytes
    }

    public var isLoopbackOnly: Bool {
        bindHost == "127.0.0.1" || bindHost == "localhost" || bindHost == "::1"
    }
}

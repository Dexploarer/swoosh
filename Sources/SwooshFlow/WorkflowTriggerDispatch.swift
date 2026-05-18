// SwooshFlow/WorkflowTriggerDispatch.swift — Admission, dispatcher, arming service
import Foundation
import SwooshTools

// MARK: - Run admission
// ═══════════════════════════════════════════════════════════════════

public struct WorkflowRunAdmissionDecision: Codable, Sendable {
    public let allowed: Bool
    public let reason: String
    public init(allowed: Bool, reason: String) { self.allowed = allowed; self.reason = reason }
}

public struct WorkflowRunAdmission: Sendable {
    private let enablementStore: any WorkflowEnablementStoring
    private let triggerStore: any WorkflowTriggerStoring

    public init(enablementStore: any WorkflowEnablementStoring, triggerStore: any WorkflowTriggerStoring) {
        self.enablementStore = enablementStore; self.triggerStore = triggerStore
    }

    public func evaluate(_ event: TriggerEvent) async throws -> WorkflowRunAdmissionDecision {
        // Check workflow enabled
        guard let enablement = try await enablementStore.get(workflowID: event.workflowID) else {
            return WorkflowRunAdmissionDecision(allowed: false, reason: "Workflow not found or not enabled.")
        }
        if enablement.state == .disabled || enablement.state == .archived {
            return WorkflowRunAdmissionDecision(allowed: false, reason: "Workflow is disabled or archived.")
        }
        // Non-manual triggers need allowTriggeredRuns
        if event.kind != .manual && !enablement.activationPolicy.allowTriggeredRuns {
            return WorkflowRunAdmissionDecision(allowed: false, reason: "Triggered runs not allowed by activation policy.")
        }
        // Check trigger armed
        if let trigger = try await triggerStore.get(id: event.triggerID) {
            if trigger.state != .armed && trigger.kind != .manual {
                return WorkflowRunAdmissionDecision(allowed: false, reason: "Trigger is not armed.")
            }
        }
        return WorkflowRunAdmissionDecision(allowed: true, reason: "Admitted.")
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Trigger dispatcher
// ═══════════════════════════════════════════════════════════════════

public actor TriggerDispatcher {
    private let eventStore: any TriggerEventStoring
    private let runQueue: WorkflowRunQueue
    private let debouncer: TriggerDebouncer
    private let rateLimiter: TriggerRateLimiter
    private let admission: WorkflowRunAdmission
    public private(set) var dispatchedCount: Int = 0

    public init(
        eventStore: any TriggerEventStoring, runQueue: WorkflowRunQueue,
        debouncer: TriggerDebouncer, rateLimiter: TriggerRateLimiter,
        admission: WorkflowRunAdmission
    ) {
        self.eventStore = eventStore; self.runQueue = runQueue
        self.debouncer = debouncer; self.rateLimiter = rateLimiter; self.admission = admission
    }

    public func handle(_ event: TriggerEvent) async throws {
        var ev = event
        try await eventStore.save(ev)

        guard await debouncer.shouldAdmit(ev) else {
            ev.status = .debounced; try await eventStore.update(ev); return
        }
        guard await rateLimiter.shouldAdmit(ev) else {
            ev.status = .rateLimited; try await eventStore.update(ev); return
        }
        let decision = try await admission.evaluate(ev)
        guard decision.allowed else {
            ev.status = .rejected; ev.rejectedAt = Date(); try await eventStore.update(ev); return
        }
        ev.status = .queued; ev.admittedAt = Date()
        let request = WorkflowRunRequest06B(
            workflowID: ev.workflowID, triggerID: ev.triggerID,
            triggerEventID: ev.id, origin: mapOrigin(ev.kind)
        )
        ev.runID = request.id
        try await eventStore.update(ev)
        await runQueue.enqueue(request)
        dispatchedCount += 1
    }

    private func mapOrigin(_ kind: WorkflowTriggerKind) -> WorkflowRunOrigin {
        switch kind {
        case .manual: return .manual
        case .schedule: return .schedule
        case .fileChanged: return .fileChanged
        case .webhook: return .webhook
        case .appEvent: return .appEvent
        case .calendarEvent: return .calendarEvent
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Trigger arming service
// ═══════════════════════════════════════════════════════════════════

public struct TriggerArmingService: Sendable {
    private let triggerStore: any WorkflowTriggerStoring
    private let validator: WorkflowTriggerValidator

    private static let webhookBindAllowed = ["127.0.0.1", "localhost", "::1"]
    private static let sensitivePaths: Set<String> = [".ssh", "Keychain", "Cookies", "Login Data", ".gnupg", ".env"]

    public init(triggerStore: any WorkflowTriggerStoring, validator: WorkflowTriggerValidator = WorkflowTriggerValidator()) {
        self.triggerStore = triggerStore; self.validator = validator
    }

    public func arm(triggerID: String) async throws -> WorkflowTrigger {
        guard var trigger = try await triggerStore.get(id: triggerID) else {
            throw TriggerError.triggerNotFound(triggerID)
        }
        let validation = validator.validate(trigger)
        guard validation.isValid else {
            throw TriggerArmingError.validationFailed(validation.errors)
        }
        // Extra arming checks
        switch trigger.configuration {
        case .fileChanged(let cfg):
            if cfg.rootID.isEmpty || cfg.rootID == "/" || cfg.rootID == "~" {
                throw TriggerArmingError.unsafeConfiguration("Full-disk file watching not allowed.")
            }
            for glob in cfg.includeGlobs {
                for sensitive in Self.sensitivePaths {
                    if glob.contains(sensitive) { throw TriggerArmingError.unsafeConfiguration("Sensitive path: \(sensitive)") }
                }
            }
        case .webhook(let cfg):
            if !cfg.localOnly { throw TriggerArmingError.unsafeConfiguration("Webhooks must be local-only.") }
        default: break
        }
        trigger.state = .armed
        trigger.updatedAt = Date()
        try await triggerStore.update(trigger)
        return trigger
    }

    public func disarm(triggerID: String) async throws -> WorkflowTrigger {
        guard var trigger = try await triggerStore.get(id: triggerID) else {
            throw TriggerError.triggerNotFound(triggerID)
        }
        trigger.state = .disabled
        trigger.updatedAt = Date()
        try await triggerStore.update(trigger)
        return trigger
    }
}

public enum TriggerArmingError: Error, Sendable {
    case validationFailed([String])
    case unsafeConfiguration(String)
}

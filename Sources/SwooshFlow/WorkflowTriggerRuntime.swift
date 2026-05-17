// SwooshFlow/WorkflowTriggerRuntime.swift — 0.6B Trigger Runtime
//
// Trigger events, dispatcher, debouncer, rate limiter, arming.
// Converts trigger events into queued workflow runs.
// Does NOT execute workflows directly — only queues them.

import Foundation
import SwooshTools

// ═══════════════════════════════════════════════════════════════════
// MARK: - Trigger event
// ═══════════════════════════════════════════════════════════════════

public struct TriggerEvent: Codable, Sendable, Identifiable {
    public let id: String
    public let triggerID: String
    public let workflowID: String
    public let kind: WorkflowTriggerKind
    public let payload: TriggerEventPayload
    public var status: TriggerEventStatus
    public let createdAt: Date
    public var admittedAt: Date?
    public var rejectedAt: Date?
    public var runID: String?

    public init(
        id: String = UUID().uuidString, triggerID: String, workflowID: String,
        kind: WorkflowTriggerKind, payload: TriggerEventPayload,
        status: TriggerEventStatus = .detected, createdAt: Date = Date()
    ) {
        self.id = id; self.triggerID = triggerID; self.workflowID = workflowID
        self.kind = kind; self.payload = payload; self.status = status; self.createdAt = createdAt
    }
}

public enum TriggerEventStatus: String, Codable, Sendable {
    case detected, debounced, rateLimited, admitted, rejected, queued, started, completed, failed
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Trigger event payloads
// ═══════════════════════════════════════════════════════════════════

public enum TriggerEventPayload: Codable, Sendable {
    case manual(ManualTriggerEventPayload)
    case schedule(ScheduleTriggerEventPayload)
    case fileChanged(FileChangedTriggerEventPayload)
    case webhook(WebhookTriggerEventPayload)
    case appEvent(AppEventTriggerEventPayload)
    case calendarEvent(CalendarTriggerEventPayload)
}

public struct ManualTriggerEventPayload: Codable, Sendable {
    public let invokedBy: String
    public let providedInputs: [String: JSONValue]
    public init(invokedBy: String = "human", providedInputs: [String: JSONValue] = [:]) {
        self.invokedBy = invokedBy; self.providedInputs = providedInputs
    }
}

public struct ScheduleTriggerEventPayload: Codable, Sendable {
    public let scheduledFor: Date
    public let firedAt: Date
    public let timezoneIdentifier: String
    public init(scheduledFor: Date = Date(), firedAt: Date = Date(), timezoneIdentifier: String = "UTC") {
        self.scheduledFor = scheduledFor; self.firedAt = firedAt; self.timezoneIdentifier = timezoneIdentifier
    }
}

public struct FileChangedTriggerEventPayload: Codable, Sendable {
    public let rootID: String
    public let changedRelativePaths: [String]
    public let eventKind: FileChangeKind
    // No file contents stored
    public init(rootID: String, changedRelativePaths: [String], eventKind: FileChangeKind = .modified) {
        self.rootID = rootID; self.changedRelativePaths = changedRelativePaths; self.eventKind = eventKind
    }
}

public enum FileChangeKind: String, Codable, Sendable { case created, modified, deleted, renamed, unknown }

public struct WebhookTriggerEventPayload: Codable, Sendable {
    public let routeID: String
    public let method: String
    public let headersPreview: [String: String]  // redacted
    public let bodyHash: String                   // never raw body
    public let receivedAt: Date
    public init(routeID: String, method: String = "POST", headersPreview: [String: String] = [:], bodyHash: String, receivedAt: Date = Date()) {
        self.routeID = routeID; self.method = method; self.headersPreview = headersPreview
        self.bodyHash = bodyHash; self.receivedAt = receivedAt
    }
}

public struct AppEventTriggerEventPayload: Codable, Sendable {
    public let bundleIdentifier: String
    public let event: AppEventKind
    public let appName: String?
    // No window contents, no screenshots
    public init(bundleIdentifier: String, event: AppEventKind, appName: String? = nil) {
        self.bundleIdentifier = bundleIdentifier; self.event = event; self.appName = appName
    }
}

public struct CalendarTriggerEventPayload: Codable, Sendable {
    public let calendarIDHash: String?   // hashed, not raw
    public let matchedRuleDescription: String
    public let eventStart: Date?
    // No raw title, location, notes, attendees
    public init(calendarIDHash: String? = nil, matchedRuleDescription: String, eventStart: Date? = nil) {
        self.calendarIDHash = calendarIDHash; self.matchedRuleDescription = matchedRuleDescription; self.eventStart = eventStart
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Trigger event store
// ═══════════════════════════════════════════════════════════════════

public protocol TriggerEventStoring: Sendable {
    func save(_ event: TriggerEvent) async throws
    func update(_ event: TriggerEvent) async throws
    func get(id: String) async throws -> TriggerEvent?
    func list(triggerID: String?, workflowID: String?, limit: Int?) async throws -> [TriggerEvent]
}

public actor InMemoryTriggerEventStore: TriggerEventStoring {
    private var events: [String: TriggerEvent] = [:]
    public init() {}
    public func save(_ e: TriggerEvent) { events[e.id] = e }
    public func update(_ e: TriggerEvent) { events[e.id] = e }
    public func get(id: String) -> TriggerEvent? { events[id] }
    public func list(triggerID: String?, workflowID: String?, limit: Int?) -> [TriggerEvent] {
        var r = Array(events.values)
        if let t = triggerID { r = r.filter { $0.triggerID == t } }
        if let w = workflowID { r = r.filter { $0.workflowID == w } }
        r.sort { $0.createdAt > $1.createdAt }
        if let l = limit { r = Array(r.prefix(l)) }
        return r
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Debouncer
// ═══════════════════════════════════════════════════════════════════

public actor TriggerDebouncer: Sendable {
    private var lastEventTimes: [String: Date] = [:]
    private let defaultDebounceSeconds: Int

    public init(defaultDebounceSeconds: Int = 30) {
        self.defaultDebounceSeconds = defaultDebounceSeconds
    }

    public func shouldAdmit(_ event: TriggerEvent) -> Bool {
        let key = event.triggerID
        let now = event.createdAt
        if let last = lastEventTimes[key] {
            let elapsed = now.timeIntervalSince(last)
            if elapsed < Double(defaultDebounceSeconds) { return false }
        }
        lastEventTimes[key] = now
        return true
    }

    public func reset(triggerID: String) { lastEventTimes.removeValue(forKey: triggerID) }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Rate limiter
// ═══════════════════════════════════════════════════════════════════

public actor TriggerRateLimiter: Sendable {
    private var eventCounts: [String: [Date]] = [:]
    private let maxEventsPerHour: Int
    private let maxRunsPerDay: Int

    public init(maxEventsPerHour: Int = 6, maxRunsPerDay: Int = 12) {
        self.maxEventsPerHour = maxEventsPerHour; self.maxRunsPerDay = maxRunsPerDay
    }

    public func shouldAdmit(_ event: TriggerEvent) -> Bool {
        let key = event.triggerID
        let now = event.createdAt
        let oneHourAgo = now.addingTimeInterval(-3600)
        let oneDayAgo = now.addingTimeInterval(-86400)

        var history = eventCounts[key] ?? []
        history = history.filter { $0 > oneDayAgo }

        let hourCount = history.filter { $0 > oneHourAgo }.count
        if hourCount >= maxEventsPerHour { return false }
        if history.count >= maxRunsPerDay { return false }

        history.append(now)
        eventCounts[key] = history
        return true
    }
}

// ═══════════════════════════════════════════════════════════════════
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

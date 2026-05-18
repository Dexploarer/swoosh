// SwooshFlow/WorkflowTriggerTypes.swift — 0.6A Native Triggers + Enablement
//
// Trigger definitions, enablement states, activation policies.
// Non-manual triggers are configured but NOT armed in 0.6A.
// No background runner, no listeners, no watchers, no timers.

import Foundation
import SwooshTools

// ═══════════════════════════════════════════════════════════════════
// MARK: - Enablement
// ═══════════════════════════════════════════════════════════════════

public struct WorkflowEnablement: Codable, Sendable, Identifiable {
    public let id: String
    public let workflowID: String
    public var state: WorkflowEnablementState
    public var activationPolicy: WorkflowActivationPolicy
    public var enabledTriggerIDs: [String]
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString, workflowID: String,
        state: WorkflowEnablementState = .disabled,
        activationPolicy: WorkflowActivationPolicy = .manualOnly,
        enabledTriggerIDs: [String] = [],
        createdAt: Date = Date(), updatedAt: Date = Date()
    ) {
        self.id = id; self.workflowID = workflowID; self.state = state
        self.activationPolicy = activationPolicy; self.enabledTriggerIDs = enabledTriggerIDs
        self.createdAt = createdAt; self.updatedAt = updatedAt
    }
}

public enum WorkflowEnablementState: String, Codable, Sendable {
    case disabled, enabledManualOnly, triggersConfiguredNotArmed, enabledWithTriggers, archived
}

public struct WorkflowActivationPolicy: Codable, Sendable {
    public let allowManualRuns: Bool
    public let allowTriggeredRuns: Bool
    public let allowUnattendedRuns: Bool
    public let requireFreshPermissionCheck: Bool

    public static let manualOnly = WorkflowActivationPolicy(
        allowManualRuns: true, allowTriggeredRuns: false,
        allowUnattendedRuns: false, requireFreshPermissionCheck: true
    )
    public static let triggerConfiguredOnly = WorkflowActivationPolicy(
        allowManualRuns: true, allowTriggeredRuns: false,
        allowUnattendedRuns: false, requireFreshPermissionCheck: true
    )
    public static let triggeredReadOnly = WorkflowActivationPolicy(
        allowManualRuns: true, allowTriggeredRuns: true,
        allowUnattendedRuns: false, requireFreshPermissionCheck: true
    )

    public init(allowManualRuns: Bool, allowTriggeredRuns: Bool, allowUnattendedRuns: Bool, requireFreshPermissionCheck: Bool) {
        self.allowManualRuns = allowManualRuns; self.allowTriggeredRuns = allowTriggeredRuns
        self.allowUnattendedRuns = allowUnattendedRuns; self.requireFreshPermissionCheck = requireFreshPermissionCheck
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Enablement store
// ═══════════════════════════════════════════════════════════════════

public protocol WorkflowEnablementStoring: Sendable {
    func save(_ e: WorkflowEnablement) async throws
    func get(workflowID: String) async throws -> WorkflowEnablement?
    func update(_ e: WorkflowEnablement) async throws
    func listEnabled() async throws -> [WorkflowEnablement]
}

public actor InMemoryEnablementStore: WorkflowEnablementStoring {
    private var items: [String: WorkflowEnablement] = [:]
    public init() {}
    public func save(_ e: WorkflowEnablement) { items[e.workflowID] = e }
    public func get(workflowID: String) -> WorkflowEnablement? { items[workflowID] }
    public func update(_ e: WorkflowEnablement) throws {
        guard items[e.workflowID] != nil else { throw TriggerError.enablementNotFound(e.workflowID) }
        items[e.workflowID] = e
    }
    public func listEnabled() -> [WorkflowEnablement] {
        items.values.filter { $0.state == .enabledManualOnly || $0.state == .triggersConfiguredNotArmed || $0.state == .enabledWithTriggers }
            .sorted { $0.updatedAt > $1.updatedAt }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Trigger model
// ═══════════════════════════════════════════════════════════════════

public struct WorkflowTrigger: Codable, Sendable, Identifiable {
    public let id: String
    public let workflowID: String
    public var name: String
    public var kind: WorkflowTriggerKind
    public var state: WorkflowTriggerState
    public var configuration: WorkflowTriggerConfiguration
    public var requiredPermissions: [SwooshPermission]
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString, workflowID: String, name: String,
        kind: WorkflowTriggerKind, state: WorkflowTriggerState = .draft,
        configuration: WorkflowTriggerConfiguration,
        requiredPermissions: [SwooshPermission] = [],
        createdAt: Date = Date(), updatedAt: Date = Date()
    ) {
        self.id = id; self.workflowID = workflowID; self.name = name
        self.kind = kind; self.state = state; self.configuration = configuration
        self.requiredPermissions = requiredPermissions; self.createdAt = createdAt; self.updatedAt = updatedAt
    }
}

public enum WorkflowTriggerKind: String, Codable, Sendable {
    case manual, schedule, fileChanged, webhook, appEvent, calendarEvent
}

public enum WorkflowTriggerState: String, Codable, Sendable {
    case draft, configured, validated, invalid, disabled, notArmedInThisMilestone, armed, paused, failed
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Trigger configurations
// ═══════════════════════════════════════════════════════════════════

public enum WorkflowTriggerConfiguration: Codable, Sendable {
    case manual(ManualTriggerConfig)
    case schedule(ScheduleTriggerConfig)
    case fileChanged(FileChangedTriggerConfig)
    case webhook(WebhookTriggerConfig)
    case appEvent(AppEventTriggerConfig)
    case calendarEvent(CalendarEventTriggerConfig)
}

public struct ManualTriggerConfig: Codable, Sendable {
    public let label: String?
    public init(label: String? = nil) { self.label = label }
}

// Schedule
public struct ScheduleTriggerConfig: Codable, Sendable {
    public let schedule: ScheduleSpec
    public let timezoneIdentifier: String
    public let humanDescription: String
    public init(schedule: ScheduleSpec, timezoneIdentifier: String = "UTC", humanDescription: String = "") {
        self.schedule = schedule; self.timezoneIdentifier = timezoneIdentifier; self.humanDescription = humanDescription
    }
}

public enum ScheduleSpec: Codable, Sendable {
    case interval(IntervalSchedule)
    case daily(DailySchedule)
    case weekly(WeeklySchedule)
    case cron(CronSchedule)
}

public struct IntervalSchedule: Codable, Sendable { public let everySeconds: Int; public init(everySeconds: Int) { self.everySeconds = everySeconds } }
public struct DailySchedule: Codable, Sendable { public let hour: Int; public let minute: Int; public init(hour: Int, minute: Int) { self.hour = hour; self.minute = minute } }
public struct WeeklySchedule: Codable, Sendable { public let weekdays: [Int]; public let hour: Int; public let minute: Int; public init(weekdays: [Int], hour: Int, minute: Int) { self.weekdays = weekdays; self.hour = hour; self.minute = minute } }
public struct CronSchedule: Codable, Sendable { public let expression: String; public init(expression: String) { self.expression = expression } }

// File changed
public struct FileChangedTriggerConfig: Codable, Sendable {
    public let rootID: String
    public let includeGlobs: [String]
    public let excludeGlobs: [String]
    public let debounceSeconds: Int
    public let recursive: Bool
    public init(rootID: String, includeGlobs: [String] = ["**/*"], excludeGlobs: [String] = [".git/**", ".build/**"], debounceSeconds: Int = 2, recursive: Bool = true) {
        self.rootID = rootID; self.includeGlobs = includeGlobs; self.excludeGlobs = excludeGlobs
        self.debounceSeconds = debounceSeconds; self.recursive = recursive
    }
}

// Webhook
public struct WebhookTriggerConfig: Codable, Sendable {
    public let routeID: String
    public let secretRef: String?
    public let localOnly: Bool
    public let expectedPayloadSchema: JSONSchema?
    public init(routeID: String = UUID().uuidString, secretRef: String? = nil, localOnly: Bool = true, expectedPayloadSchema: JSONSchema? = nil) {
        self.routeID = routeID; self.secretRef = secretRef; self.localOnly = localOnly; self.expectedPayloadSchema = expectedPayloadSchema
    }
}

// App event
public struct AppEventTriggerConfig: Codable, Sendable {
    public let bundleIdentifier: String
    public let event: AppEventKind
    public init(bundleIdentifier: String, event: AppEventKind) { self.bundleIdentifier = bundleIdentifier; self.event = event }
}

public enum AppEventKind: String, Codable, Sendable { case launched, activated, terminated }

// Calendar event
public struct CalendarEventTriggerConfig: Codable, Sendable {
    public let calendarIDs: [String]?
    public let matchTitleContains: String?
    public let startsWithinMinutes: Int
    public init(calendarIDs: [String]? = nil, matchTitleContains: String? = nil, startsWithinMinutes: Int = 15) {
        self.calendarIDs = calendarIDs; self.matchTitleContains = matchTitleContains; self.startsWithinMinutes = startsWithinMinutes
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Trigger store
// ═══════════════════════════════════════════════════════════════════

public protocol WorkflowTriggerStoring: Sendable {
    func save(_ trigger: WorkflowTrigger) async throws
    func update(_ trigger: WorkflowTrigger) async throws
    func get(id: String) async throws -> WorkflowTrigger?
    func list(workflowID: String?) async throws -> [WorkflowTrigger]
    func delete(id: String) async throws
}

public actor InMemoryTriggerStore: WorkflowTriggerStoring {
    private var triggers: [String: WorkflowTrigger] = [:]
    public init() {}
    public func save(_ t: WorkflowTrigger) { triggers[t.id] = t }
    public func update(_ t: WorkflowTrigger) throws {
        guard triggers[t.id] != nil else { throw TriggerError.triggerNotFound(t.id) }
        triggers[t.id] = t
    }
    public func get(id: String) -> WorkflowTrigger? { triggers[id] }
    public func list(workflowID: String?) -> [WorkflowTrigger] {
        let all = Array(triggers.values)
        if let w = workflowID { return all.filter { $0.workflowID == w }.sorted { $0.createdAt > $1.createdAt } }
        return all.sorted { $0.createdAt > $1.createdAt }
    }
    public func delete(id: String) throws {
        guard triggers.removeValue(forKey: id) != nil else { throw TriggerError.triggerNotFound(id) }
    }
}

// ═══════════════════════════════════════════════════════════════════

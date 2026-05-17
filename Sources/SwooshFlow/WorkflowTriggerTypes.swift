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
// MARK: - Validation
// ═══════════════════════════════════════════════════════════════════

public struct WorkflowTriggerValidationResult: Codable, Sendable {
    public let isValid: Bool
    public let warnings: [String]
    public let errors: [String]
    public let requiredPermissions: [SwooshPermission]
    public let milestoneLimitations: [String]

    public init(isValid: Bool, warnings: [String] = [], errors: [String] = [],
                requiredPermissions: [SwooshPermission] = [], milestoneLimitations: [String] = []) {
        self.isValid = isValid; self.warnings = warnings; self.errors = errors
        self.requiredPermissions = requiredPermissions; self.milestoneLimitations = milestoneLimitations
    }
}

public struct WorkflowTriggerValidator: Sendable {
    private static let sensitivePaths = [".ssh", "Keychain", "Cookies", "Login Data", ".gnupg", ".env"]
    public init() {}

    public func validate(_ trigger: WorkflowTrigger) -> WorkflowTriggerValidationResult {
        var errors: [String] = []
        var warnings: [String] = []
        var perms: [SwooshPermission] = []
        var limits: [String] = []

        switch trigger.configuration {
        case .manual:
            perms = [.workflowRun]

        case .schedule(let cfg):
            perms = [.workflowRead]
            limits.append("Schedule triggers are not armed in 0.6A.")
            switch cfg.schedule {
            case .daily(let d):
                if d.hour < 0 || d.hour > 23 { errors.append("Invalid hour: \(d.hour)") }
                if d.minute < 0 || d.minute > 59 { errors.append("Invalid minute: \(d.minute)") }
            case .weekly(let w):
                if w.weekdays.isEmpty { errors.append("No weekdays specified.") }
                for wd in w.weekdays { if wd < 1 || wd > 7 { errors.append("Invalid weekday: \(wd)") } }
            case .interval(let i):
                if i.everySeconds < 60 { errors.append("Interval must be ≥ 60 seconds.") }
            case .cron(let c):
                if c.expression.isEmpty { errors.append("Cron expression is empty.") }
            }

        case .fileChanged(let cfg):
            perms = [.fileRead, .workflowRead]
            limits.append("File watchers are not armed in 0.6A.")
            if cfg.rootID.isEmpty { errors.append("Root ID is required.") }
            if cfg.rootID == "/" || cfg.rootID == "~" || cfg.rootID == "*" {
                errors.append("Full-disk watching is not allowed.")
            }
            for glob in cfg.includeGlobs {
                for sensitive in Self.sensitivePaths {
                    if glob.contains(sensitive) { errors.append("Sensitive path '\(sensitive)' is not allowed in include globs.") }
                }
            }

        case .webhook(let cfg):
            perms = [.workflowRead]
            limits.append("Webhook listeners are not armed in 0.6A.")
            if !cfg.localOnly { errors.append("Webhooks must be local-only in 0.6A.") }

        case .appEvent(let cfg):
            perms = [.workflowRead]
            limits.append("App event listeners are not armed in 0.6A.")
            if cfg.bundleIdentifier.isEmpty { errors.append("Bundle identifier is required.") }
            if !cfg.bundleIdentifier.contains(".") { errors.append("Invalid bundle identifier format.") }

        case .calendarEvent:
            perms = [.workflowRead]
            limits.append("Calendar listeners are not armed in 0.6A.")
            warnings.append("Calendar triggers require calendarRead permission.")
        }

        return WorkflowTriggerValidationResult(
            isValid: errors.isEmpty, warnings: warnings, errors: errors,
            requiredPermissions: perms, milestoneLimitations: limits
        )
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Preview
// ═══════════════════════════════════════════════════════════════════

public struct WorkflowTriggerPreview: Codable, Sendable, Identifiable {
    public let id: String
    public let triggerID: String
    public let workflowID: String
    public let kind: WorkflowTriggerKind
    public let summaryMarkdown: String
    public let nextFireTimes: [Date]
    public let watchedPathsPreview: [String]
    public let requiredPermissions: [SwooshPermission]
    public let milestoneLimitations: [String]

    public init(id: String = UUID().uuidString, triggerID: String, workflowID: String,
                kind: WorkflowTriggerKind, summaryMarkdown: String,
                nextFireTimes: [Date] = [], watchedPathsPreview: [String] = [],
                requiredPermissions: [SwooshPermission] = [], milestoneLimitations: [String] = []) {
        self.id = id; self.triggerID = triggerID; self.workflowID = workflowID
        self.kind = kind; self.summaryMarkdown = summaryMarkdown
        self.nextFireTimes = nextFireTimes; self.watchedPathsPreview = watchedPathsPreview
        self.requiredPermissions = requiredPermissions; self.milestoneLimitations = milestoneLimitations
    }
}

public struct WorkflowTriggerPreviewer: Sendable {
    public init() {}

    public func preview(_ trigger: WorkflowTrigger) -> WorkflowTriggerPreview {
        let validation = WorkflowTriggerValidator().validate(trigger)
        switch trigger.configuration {
        case .manual:
            return WorkflowTriggerPreview(
                triggerID: trigger.id, workflowID: trigger.workflowID, kind: .manual,
                summaryMarkdown: "Manual trigger. Run with `/workflow execute \(trigger.workflowID)`.",
                requiredPermissions: validation.requiredPermissions
            )
        case .schedule(let cfg):
            let times = computeNextFireTimes(cfg, count: 3)
            var md = "## Schedule: \(cfg.humanDescription)\n\nTimezone: \(cfg.timezoneIdentifier)\n"
            md += "\n⚠ Not armed in 0.6A."
            return WorkflowTriggerPreview(
                triggerID: trigger.id, workflowID: trigger.workflowID, kind: .schedule,
                summaryMarkdown: md, nextFireTimes: times,
                requiredPermissions: validation.requiredPermissions,
                milestoneLimitations: validation.milestoneLimitations
            )
        case .fileChanged(let cfg):
            var md = "## File Change Trigger\n\nRoot: \(cfg.rootID)\nInclude: \(cfg.includeGlobs.joined(separator: ", "))\nExclude: \(cfg.excludeGlobs.joined(separator: ", "))\n"
            md += "\n⚠ File watchers not armed in 0.6A."
            return WorkflowTriggerPreview(
                triggerID: trigger.id, workflowID: trigger.workflowID, kind: .fileChanged,
                summaryMarkdown: md, watchedPathsPreview: cfg.includeGlobs,
                requiredPermissions: validation.requiredPermissions,
                milestoneLimitations: validation.milestoneLimitations
            )
        case .webhook:
            return WorkflowTriggerPreview(
                triggerID: trigger.id, workflowID: trigger.workflowID, kind: .webhook,
                summaryMarkdown: "Webhook trigger (local-only).\n\n⚠ Listener not armed in 0.6A.",
                requiredPermissions: validation.requiredPermissions,
                milestoneLimitations: validation.milestoneLimitations
            )
        case .appEvent(let cfg):
            return WorkflowTriggerPreview(
                triggerID: trigger.id, workflowID: trigger.workflowID, kind: .appEvent,
                summaryMarkdown: "App event: \(cfg.bundleIdentifier) → \(cfg.event.rawValue)\n\n⚠ Not armed in 0.6A.",
                requiredPermissions: validation.requiredPermissions,
                milestoneLimitations: validation.milestoneLimitations
            )
        case .calendarEvent(let cfg):
            let match = cfg.matchTitleContains ?? "(any)"
            return WorkflowTriggerPreview(
                triggerID: trigger.id, workflowID: trigger.workflowID, kind: .calendarEvent,
                summaryMarkdown: "Calendar: events matching \"\(match)\" starting within \(cfg.startsWithinMinutes) min.\n\n⚠ Not armed in 0.6A.",
                requiredPermissions: validation.requiredPermissions,
                milestoneLimitations: validation.milestoneLimitations
            )
        }
    }

    private func computeNextFireTimes(_ cfg: ScheduleTriggerConfig, count: Int) -> [Date] {
        let cal = Calendar.current
        let now = Date()
        var times: [Date] = []
        switch cfg.schedule {
        case .daily(let d):
            for i in 0..<count {
                if let day = cal.date(byAdding: .day, value: i, to: now),
                   let fire = cal.date(bySettingHour: d.hour, minute: d.minute, second: 0, of: day) {
                    times.append(fire)
                }
            }
        case .weekly(let w):
            var cursor = now
            while times.count < count {
                let wd = cal.component(.weekday, from: cursor)
                if w.weekdays.contains(wd),
                   let fire = cal.date(bySettingHour: w.hour, minute: w.minute, second: 0, of: cursor),
                   fire > now { times.append(fire) }
                cursor = cal.date(byAdding: .day, value: 1, to: cursor)!
            }
        case .interval(let i):
            for n in 1...count { times.append(now.addingTimeInterval(Double(n * i.everySeconds))) }
        case .cron:
            break // Cron parsing deferred
        }
        return times
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Errors
// ═══════════════════════════════════════════════════════════════════

public enum TriggerError: Error, Sendable {
    case triggerNotFound(String)
    case enablementNotFound(String)
    case workflowNotFound(String)
    case workflowArchived(String)
    case nonManualTriggerCannotFire
    case webhookMustBeLocalOnly
}

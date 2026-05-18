// SwooshFlow/WorkflowTriggerValidation.swift — Trigger validation, preview, errors
import Foundation
import SwooshTools

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

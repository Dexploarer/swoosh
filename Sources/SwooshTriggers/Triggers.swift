// SwooshTriggers/Triggers.swift — Native event-driven scheduler
//
// More Apple-native than cron. Time, file, app, event, focus, webhook.

import Foundation

// MARK: - Trigger definition

/// A native trigger that is more expressive than cron.
/// Uses Apple platform events, file system, calendar, focus modes, etc.
public struct SwooshTrigger: Codable, Sendable, Identifiable {
    public let id: UUID
    public var name: String
    public var event: TriggerEvent
    public var action: TriggerAction
    public var isEnabled: Bool
    public var lastFired: Date?
    public var fireCount: Int

    public init(
        id: UUID = UUID(),
        name: String,
        event: TriggerEvent,
        action: TriggerAction,
        isEnabled: Bool = true,
        lastFired: Date? = nil,
        fireCount: Int = 0
    ) {
        self.id = id
        self.name = name
        self.event = event
        self.action = action
        self.isEnabled = isEnabled
        self.lastFired = lastFired
        self.fireCount = fireCount
    }
}

// MARK: - Trigger events

public enum TriggerEvent: Codable, Sendable {
    // ── Time ────────────────────────────────────────────────────
    case cron(expression: String)
    case naturalLanguage(schedule: String)
    case everyWeekday(at: String)
    case interval(seconds: TimeInterval)

    // ── File system ─────────────────────────────────────────────
    case fileChanged(path: String)
    case fileCreated(inDirectory: String)
    case fileDeleted(path: String)

    // ── App / system ────────────────────────────────────────────
    case appLaunched(bundleID: String)
    case appTerminated(bundleID: String)
    case focusModeChanged(to: String)
    case screenLocked
    case screenUnlocked
    case wifiChanged(to: String)
    case batteryBelow(percent: Int)
    case batteryAbove(percent: Int)
    case devicePluggedIn
    case deviceUnplugged

    // ── Calendar ────────────────────────────────────────────────
    case calendarEventStarts(minutesBefore: Int)
    case calendarEventEnds(calendarName: String?)

    // ── Repository ──────────────────────────────────────────────
    case gitPush(repoPath: String)
    case gitCommit(repoPath: String)
    case ciFailed(repoPath: String)

    // ── Network ─────────────────────────────────────────────────
    case webhookReceived(path: String)
    case emailReceived(filter: String)

    // ── Shortcuts ───────────────────────────────────────────────
    case shortcutInvoked(name: String)

    // ── Manual ──────────────────────────────────────────────────
    case manual
}

// MARK: - Trigger actions

public enum TriggerAction: Codable, Sendable {
    /// Run an agent with this prompt in a fresh session.
    case agentRun(prompt: String, modelRoute: String?)

    /// Run a named workflow.
    case workflowRun(workflowID: UUID)

    /// Run a shell command.
    case shellCommand(command: String)

    /// Send a notification.
    case notify(title: String, body: String)

    /// Invoke a Shortcut.
    case shortcut(name: String)
}

// MARK: - Trigger registry actor

public actor TriggerRegistry {
    private var triggers: [UUID: SwooshTrigger] = [:]

    public init() {}

    public func register(_ trigger: SwooshTrigger) {
        triggers[trigger.id] = trigger
    }

    public func remove(_ id: UUID) {
        triggers.removeValue(forKey: id)
    }

    public func enable(_ id: UUID) {
        triggers[id]?.isEnabled = true
    }

    public func disable(_ id: UUID) {
        triggers[id]?.isEnabled = false
    }

    public func all() -> [SwooshTrigger] {
        Array(triggers.values).sorted { $0.name < $1.name }
    }

    public func enabled() -> [SwooshTrigger] {
        all().filter { $0.isEnabled }
    }

    public func markFired(_ id: UUID) {
        triggers[id]?.lastFired = Date()
        triggers[id]?.fireCount += 1
    }
}

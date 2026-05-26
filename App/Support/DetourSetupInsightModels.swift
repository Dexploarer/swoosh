// DetourSetupInsightModels.swift — secret-safe setup insight projection models (0.5A)

import Foundation

enum DetourSetupInsightCategory: String, CaseIterable, Codable, Equatable, Sendable {
    case setupChecks
    case accounts
    case credentials
    case connectors
    case mcpServers
    case permissions
    case relationships
    case providers
    case goalsSchedules
    case appActivitySignals
    case capabilitySummary

    var label: String {
        switch self {
        case .setupChecks: "Setup checks"
        case .accounts: "Accounts"
        case .credentials: "Credentials"
        case .connectors: "Connectors"
        case .mcpServers: "MCP servers"
        case .permissions: "Permissions"
        case .relationships: "Relationships"
        case .providers: "Providers"
        case .goalsSchedules: "Goals and schedules"
        case .appActivitySignals: "App and activity signals"
        case .capabilitySummary: "Capability summary"
        }
    }
}

enum DetourSetupInsightOwner: String, Codable, Equatable, Sendable {
    case user
    case agent
    case shared
    case unknown

    var label: String {
        switch self {
        case .user: "User"
        case .agent: "Agent"
        case .shared: "Shared"
        case .unknown: "Unknown"
        }
    }
}

enum DetourSetupInsightStatus: String, Codable, Equatable, Sendable {
    case selected
    case using
    case removed
    case pending
    case verified
    case failed
    case blocked
    case needsPermission
    case needsConfiguration
    case unknown

    var label: String {
        switch self {
        case .selected: "Selected"
        case .using: "Using"
        case .removed: "Not using"
        case .pending: "Pending"
        case .verified: "Verified"
        case .failed: "Failed"
        case .blocked: "Blocked"
        case .needsPermission: "Needs permission"
        case .needsConfiguration: "Needs configuration"
        case .unknown: "Unknown"
        }
    }

    var needsAttention: Bool {
        switch self {
        case .failed, .blocked, .needsPermission, .needsConfiguration, .unknown:
            true
        case .selected, .using, .removed, .pending, .verified:
            false
        }
    }
}

enum DetourSetupInsightActionKind: String, Codable, Equatable, Sendable {
    case use
    case remove
    case scopeUser
    case scopeAgent
    case grantPermission
    case configure
    case openDoctor
    case openRelationshipQA

    var label: String {
        switch self {
        case .use: "Use"
        case .remove: "Remove"
        case .scopeUser: "Use as me"
        case .scopeAgent: "Use as agent"
        case .grantPermission: "Grant access"
        case .configure: "Configure"
        case .openDoctor: "Open Doctor"
        case .openRelationshipQA: "Discuss"
        }
    }
}

struct DetourSetupInsightAction: Codable, Equatable, Sendable {
    var kind: DetourSetupInsightActionKind
    var title: String
    var targetID: String

    init(kind: DetourSetupInsightActionKind, title: String, targetID: String) {
        self.kind = kind
        self.title = DetourSetupInsightRedaction.display(title)
        self.targetID = targetID
    }
}

enum DetourSetupInsightHealthState: String, Codable, Equatable, Sendable {
    case healthy
    case unavailable
    case needsAction
    case failed
    case notChecked
    case unknown

    var label: String {
        switch self {
        case .healthy: "Healthy"
        case .unavailable: "Unavailable"
        case .needsAction: "Needs action"
        case .failed: "Failed"
        case .notChecked: "Not checked"
        case .unknown: "Unknown"
        }
    }
}

struct DetourSetupInsightHealth: Codable, Equatable, Sendable {
    var state: DetourSetupInsightHealthState
    var title: String
    var detail: String?
    var checkedAt: Date?
    var sourceLabel: String?

    init(
        state: DetourSetupInsightHealthState,
        title: String,
        detail: String? = nil,
        checkedAt: Date? = nil,
        sourceLabel: String? = nil
    ) {
        self.state = state
        self.title = DetourSetupInsightRedaction.display(title)
        self.detail = DetourSetupInsightRedaction.displayOptional(detail)
        self.checkedAt = checkedAt
        self.sourceLabel = DetourSetupInsightRedaction.displayOptional(sourceLabel)
    }
}

enum DetourSetupInsightDoctorActionKind: String, Codable, Equatable, Sendable {
    case openDoctor
    case openSettings
    case requestPermission
    case configureCredential
    case rerunSetup
    case runCommand

    var label: String {
        switch self {
        case .openDoctor: "Open Doctor"
        case .openSettings: "Open settings"
        case .requestPermission: "Request permission"
        case .configureCredential: "Configure saved access"
        case .rerunSetup: "Run setup again"
        case .runCommand: "Run command"
        }
    }
}

struct DetourSetupInsightDoctorAction: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var kind: DetourSetupInsightDoctorActionKind
    var title: String
    var detail: String?
    var command: [String]?

    init(
        id: String,
        kind: DetourSetupInsightDoctorActionKind,
        title: String,
        detail: String? = nil,
        command: [String]? = nil
    ) {
        self.id = DetourSetupInsightRedaction.stableID(prefix: "doctor", components: [id])
        self.kind = kind
        self.title = DetourSetupInsightRedaction.display(title)
        self.detail = DetourSetupInsightRedaction.displayOptional(detail)
        self.command = command?.map(DetourSetupInsightRedaction.display).filter { !$0.isEmpty }
    }
}

struct DetourSetupInsightItem: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var category: DetourSetupInsightCategory
    var title: String
    var subtitle: String?
    var detail: String
    var sourceLabel: String?
    var owner: DetourSetupInsightOwner
    var status: DetourSetupInsightStatus
    var health: DetourSetupInsightHealth?
    var doctor: String?
    var doctorActions: [DetourSetupInsightDoctorAction]
    var count: Int?
    var actions: [DetourSetupInsightAction]

    init(
        id: String,
        category: DetourSetupInsightCategory,
        title: String,
        subtitle: String? = nil,
        detail: String,
        sourceLabel: String? = nil,
        owner: DetourSetupInsightOwner,
        status: DetourSetupInsightStatus,
        health: DetourSetupInsightHealth? = nil,
        doctor: String? = nil,
        doctorActions: [DetourSetupInsightDoctorAction] = [],
        count: Int? = nil,
        actions: [DetourSetupInsightAction] = []
    ) {
        self.id = id
        self.category = category
        self.title = DetourSetupInsightRedaction.display(title)
        self.subtitle = DetourSetupInsightRedaction.displayOptional(subtitle)
        self.detail = DetourSetupInsightRedaction.display(detail)
        self.sourceLabel = DetourSetupInsightRedaction.displayOptional(sourceLabel)
        self.owner = owner
        self.status = status
        self.health = health
        self.doctor = DetourSetupInsightRedaction.displayOptional(doctor)
        self.doctorActions = doctorActions
        self.count = count
        self.actions = actions
    }
}

struct DetourSetupInsightSection: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var subtitle: String?
    var detail: String
    var items: [DetourSetupInsightItem]

    init(
        id: String,
        title: String,
        subtitle: String? = nil,
        detail: String,
        items: [DetourSetupInsightItem]
    ) {
        self.id = id
        self.title = DetourSetupInsightRedaction.display(title)
        self.subtitle = DetourSetupInsightRedaction.displayOptional(subtitle)
        self.detail = DetourSetupInsightRedaction.display(detail)
        self.items = items
    }
}

struct DetourSetupInsightChartPoint: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var label: String
    var value: Double
    var category: DetourSetupInsightCategory?
    var status: DetourSetupInsightStatus?

    init(
        id: String,
        label: String,
        value: Double,
        category: DetourSetupInsightCategory? = nil,
        status: DetourSetupInsightStatus? = nil
    ) {
        self.id = DetourSetupInsightRedaction.stableID(prefix: "chart", components: [id, label])
        self.label = DetourSetupInsightRedaction.display(label)
        self.value = value
        self.category = category
        self.status = status
    }
}

struct DetourSetupCapabilitySummary: Codable, Equatable, Sendable {
    var total: Int
    var verified: Int
    var using: Int
    var pending: Int
    var blocked: Int
    var removed: Int
    var unknown: Int
    var chartPoints: [DetourSetupInsightChartPoint]

    init(
        total: Int? = nil,
        verified: Int,
        using: Int,
        pending: Int = 0,
        blocked: Int,
        removed: Int,
        unknown: Int = 0,
        chartPoints: [DetourSetupInsightChartPoint] = []
    ) {
        self.total = total ?? verified + using + pending + blocked + removed + unknown
        self.verified = verified
        self.using = using
        self.pending = pending
        self.blocked = blocked
        self.removed = removed
        self.unknown = unknown
        self.chartPoints = chartPoints
    }

    var needsAttention: Int {
        blocked + unknown
    }

    var plainText: String {
        [
            "\(total) total",
            "\(verified) verified",
            "\(using) selected",
            "\(pending) pending",
            "\(needsAttention) need attention",
            "\(removed) not using",
        ].joined(separator: " · ")
    }
}

struct DetourSetupInsightSnapshot: Codable, Equatable, Sendable {
    var sections: [DetourSetupInsightSection]
    var summary: DetourSetupCapabilitySummary
    var generatedAt: Date?

    init(
        sections: [DetourSetupInsightSection],
        summary: DetourSetupCapabilitySummary,
        generatedAt: Date? = nil
    ) {
        self.sections = sections
        self.summary = summary
        self.generatedAt = generatedAt
    }

    var isEmpty: Bool {
        sections.allSatisfy(\.items.isEmpty)
    }
}

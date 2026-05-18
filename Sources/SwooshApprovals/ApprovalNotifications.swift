// SwooshApprovals/ApprovalNotifications.swift — Notification policy, routing, gate factory
import Foundation
import SwooshTools

// MARK: - Errors
// ═══════════════════════════════════════════════════════════════════

public enum UnifiedApprovalError: Error, Sendable {
    case approvalNotFound(String)
    case alreadyResolved(String)
    case approvalExpired(String)
    case onlyHumanCanResolve
    case confirmationRequired(String)
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Notification policy
// ═══════════════════════════════════════════════════════════════════

public struct NotificationPolicy: Codable, Sendable {
    public let enabled: Bool
    public let notifyForLowRisk: Bool
    public let notifyForMediumRisk: Bool
    public let notifyForHighRisk: Bool
    public let notifyForCriticalRisk: Bool
    public let includeSensitivePreviews: Bool
    public let maxTitleLength: Int
    public let maxBodyLength: Int

    public static let safeDefault = NotificationPolicy(
        enabled: true, notifyForLowRisk: false, notifyForMediumRisk: true,
        notifyForHighRisk: true, notifyForCriticalRisk: true,
        includeSensitivePreviews: false, maxTitleLength: 80, maxBodyLength: 160
    )

    public init(enabled: Bool, notifyForLowRisk: Bool, notifyForMediumRisk: Bool,
                notifyForHighRisk: Bool, notifyForCriticalRisk: Bool,
                includeSensitivePreviews: Bool, maxTitleLength: Int, maxBodyLength: Int) {
        self.enabled = enabled; self.notifyForLowRisk = notifyForLowRisk
        self.notifyForMediumRisk = notifyForMediumRisk; self.notifyForHighRisk = notifyForHighRisk
        self.notifyForCriticalRisk = notifyForCriticalRisk; self.includeSensitivePreviews = includeSensitivePreviews
        self.maxTitleLength = maxTitleLength; self.maxBodyLength = maxBodyLength
    }

    public func shouldNotify(risk: ToolRisk) -> Bool {
        guard enabled else { return false }
        switch risk {
        case .readOnly: return false
        case .low: return notifyForLowRisk
        case .medium: return notifyForMediumRisk
        case .high: return notifyForHighRisk
        case .critical: return notifyForCriticalRisk
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Notification redactor
// ═══════════════════════════════════════════════════════════════════

public struct NotificationRedactor: Sendable {
    private static let secretPatterns = [
        "-----BEGIN", "PRIVATE KEY", "sk_", "0x[0-9a-fA-F]{40,}",
        "xprv", "xpub", "seed:", "mnemonic:", "cookie:", "session_token",
    ]

    public init() {}

    public func redactTitle(_ title: String, maxLength: Int = 80) -> String {
        truncate(scrub(title), maxLength: maxLength)
    }

    public func redactBody(_ body: String, maxLength: Int = 160) -> String {
        truncate(scrub(body), maxLength: maxLength)
    }

    public func scrub(_ text: String) -> String {
        var value = text
        for pattern in Self.secretPatterns {
            if value.contains(pattern) { value = value.replacingOccurrences(of: pattern, with: "[REDACTED]") }
        }
        return value
    }

    private func truncate(_ text: String, maxLength: Int) -> String {
        if text.count <= maxLength { return text }
        return String(text.prefix(maxLength - 1)) + "…"
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Notification payload
// ═══════════════════════════════════════════════════════════════════

public struct ApprovalNotificationPayload: Codable, Sendable {
    public let approvalID: String
    public let kind: ApprovalKind06C
    public let risk: ToolRisk
    public let title: String
    public let body: String
    public let createdAt: Date

    public init(approvalID: String, kind: ApprovalKind06C, risk: ToolRisk,
                title: String, body: String, createdAt: Date = Date()) {
        self.approvalID = approvalID; self.kind = kind; self.risk = risk
        self.title = title; self.body = body; self.createdAt = createdAt
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Notification router
// ═══════════════════════════════════════════════════════════════════

public protocol NotificationRouting: Sendable {
    func notifyApprovalPending(_ approval: UnifiedApproval) async throws
    func notifyWorkflowCompleted(workflowName: String) async throws
    func notifyWorkflowFailed(workflowName: String, error: String) async throws
}

public actor LocalNotificationRouter: NotificationRouting {
    private let policy: NotificationPolicy
    private let redactor: NotificationRedactor
    public private(set) var isMuted: Bool = false
    public private(set) var sentPayloads: [ApprovalNotificationPayload] = []

    public init(policy: NotificationPolicy = .safeDefault, redactor: NotificationRedactor = NotificationRedactor()) {
        self.policy = policy; self.redactor = redactor
    }

    public func mute() { isMuted = true }
    public func unmute() { isMuted = false }

    public func notifyApprovalPending(_ approval: UnifiedApproval) async throws {
        guard !isMuted && policy.shouldNotify(risk: approval.risk) else { return }
        let title = redactor.redactTitle(notificationTitle(approval), maxLength: policy.maxTitleLength)
        let body = redactor.redactBody(notificationBody(approval), maxLength: policy.maxBodyLength)
        let payload = ApprovalNotificationPayload(
            approvalID: approval.id, kind: approval.kind, risk: approval.risk,
            title: title, body: body
        )
        sentPayloads.append(payload)
    }

    public func notifyWorkflowCompleted(workflowName: String) async throws {
        guard !isMuted else { return }
        let payload = ApprovalNotificationPayload(
            approvalID: "", kind: .workflowGate, risk: .readOnly,
            title: "Workflow completed", body: redactor.redactBody(workflowName)
        )
        sentPayloads.append(payload)
    }

    public func notifyWorkflowFailed(workflowName: String, error: String) async throws {
        guard !isMuted else { return }
        let payload = ApprovalNotificationPayload(
            approvalID: "", kind: .workflowGate, risk: .medium,
            title: "Workflow failed", body: redactor.redactBody("\(workflowName): \(error)")
        )
        sentPayloads.append(payload)
    }

    private func notificationTitle(_ approval: UnifiedApproval) -> String {
        switch approval.risk {
        case .high, .critical: return "High-risk Swoosh approval"
        default: return "Swoosh needs approval"
        }
    }

    private func notificationBody(_ approval: UnifiedApproval) -> String {
        approval.summary
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Gate → UnifiedApproval factory
// ═══════════════════════════════════════════════════════════════════

public struct UnifiedApprovalFactory: Sendable {
    private let expirationPolicy: ApprovalExpirationPolicy

    public init(expirationPolicy: ApprovalExpirationPolicy = .default) {
        self.expirationPolicy = expirationPolicy
    }

    public func forWorkflowGate(
        gateID: String, runID: String, stepID: String, stepTitle: String,
        toolName: String, risk: ToolRisk, humanSummary: String,
        riskWarnings: [String] = [], rollbackHint: String? = nil, workflowName: String
    ) -> UnifiedApproval {
        let ttl = expirationPolicy.ttl(for: risk)
        let confirmation: ConfirmationRequirement = risk == .high ? .typeContains("Approve") : .clickOnly
        return UnifiedApproval(
            kind: .workflowGate, title: "Workflow approval: \(stepTitle)",
            summary: "\(workflowName) is paused at \(toolName).",
            source: ApprovalSource(runID: runID, stepID: stepID, gateID: gateID),
            risk: risk,
            preview: ApprovalPreview06C(
                humanSummary: humanSummary, commandPreview: toolName,
                riskWarnings: riskWarnings, rollbackHint: rollbackHint
            ),
            confirmationRequirement: confirmation,
            expiresAt: Date().addingTimeInterval(ttl)
        )
    }

    public func fromToolApproval(_ record: ApprovalRecord) -> UnifiedApproval {
        let ttl = expirationPolicy.ttl(for: record.risk)
        return UnifiedApproval(
            kind: .toolCall, title: "Tool approval: \(record.toolName)",
            summary: "Agent requests \(record.toolName) (risk: \(record.risk.rawValue)).",
            source: ApprovalSource(sessionID: record.sessionID, toolCallID: record.id, origin: record.origin),
            risk: record.risk,
            preview: ApprovalPreview06C(humanSummary: record.inputPreview),
            expiresAt: Date().addingTimeInterval(ttl)
        )
    }

    public func forTriggerArming(triggerID: String, workflowName: String, triggerKind: String) -> UnifiedApproval {
        UnifiedApproval(
            kind: .triggerArming, title: "Arm trigger: \(triggerKind)",
            summary: "Arm \(triggerKind) trigger for \(workflowName).",
            source: ApprovalSource(triggerID: triggerID),
            risk: .high,
            preview: ApprovalPreview06C(humanSummary: "Read-only steps may run unattended. Risky steps pause.", actionType: .armTrigger),
            confirmationRequirement: .typeContains("Arm"),
            expiresAt: Date().addingTimeInterval(expirationPolicy.ttl(for: .high))
        )
    }

    public func forMemoryCandidate(memoryID: String, summary: String) -> UnifiedApproval {
        UnifiedApproval(
            kind: .memoryCandidate, title: "Memory review",
            summary: "Review proposed memory.",
            source: ApprovalSource(),
            risk: .low,
            preview: ApprovalPreview06C(humanSummary: summary, actionType: .approveMemory)
        )
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Menu bar status model
// ═══════════════════════════════════════════════════════════════════

public struct MenuBarStatus: Codable, Sendable {
    public let pendingCount: Int
    public let highRiskPending: Bool
    public let runnerActive: Bool
    public let runnerPaused: Bool

    public init(pendingCount: Int, highRiskPending: Bool, runnerActive: Bool, runnerPaused: Bool) {
        self.pendingCount = pendingCount; self.highRiskPending = highRiskPending
        self.runnerActive = runnerActive; self.runnerPaused = runnerPaused
    }
}

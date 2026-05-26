// DetourHomeInboxModel.swift — daemon-backed universal inbox projection (0.5A)

import Combine
import Foundation

@MainActor
final class DetourHomeInboxModel: ObservableObject {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded(Date)
        case failed(String)

        var label: String {
            switch self {
            case .idle: "Not checked"
            case .loading: "Refreshing"
            case .loaded: "Live"
            case .failed: "Offline"
            }
        }
    }

    @Published private(set) var state: LoadState = .idle
    @Published private(set) var items: [DetourHomeInboxItem] = []
    @Published private(set) var connectedSources: [String] = []

    var pendingCount: Int {
        items.filter { $0.kind == .approval }.count
    }

    func refresh() {
        guard state != .loading else { return }
        state = .loading
        Task { await load() }
    }

    func markOffline(_ message: String) {
        items = []
        connectedSources = []
        state = .failed(DetourSetupInsightRedaction.display(message))
    }

    private func load() async {
        do {
            let client = try await DetourHomeDaemonClient.makeEnsuringDaemon()
            async let transcript = client.transcript(sessionID: "default")
            async let approvals = client.approvals()
            async let audit = client.audit()
            async let adapters = client.chatAdapters()
            let result = try await Self.inboxItems(
                transcript: transcript,
                approvals: approvals,
                audit: audit,
                adapters: adapters
            )
            items = result.items
            connectedSources = result.connectedSources
            state = .loaded(Date())
        } catch {
            items = []
            connectedSources = []
            state = .failed(DetourHomeDaemonClient.display(error))
        }
    }

    private static func inboxItems(
        transcript: TranscriptResponse,
        approvals: ApprovalsResponse,
        audit: AuditEventsResponse,
        adapters: ChatAdaptersResponse
    ) -> (items: [DetourHomeInboxItem], connectedSources: [String]) {
        let transcriptItems = transcript.messages
            .filter { $0.role != .system }
            .suffix(24)
            .map(DetourHomeInboxItem.init(message:))
        let approvalItems = approvals.pending.map(DetourHomeInboxItem.init(approval:))
        let auditItems = audit.events
            .filter(isMessageRelated)
            .prefix(12)
            .map(DetourHomeInboxItem.init(event:))
        let items = (approvalItems + transcriptItems + auditItems)
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(40)
        return (Array(items), connectedSources(adapters))
    }

    private static func connectedSources(_ response: ChatAdaptersResponse) -> [String] {
        let names = response.adapters
            .filter { $0.enabled && $0.configured }
            .map(\.displayName)
        let stateNames = response.stateAdapters
            .filter { $0.enabled && $0.configured }
            .map(\.displayName)
        return Array(Set(names + stateNames)).sorted()
    }

    private static func isMessageRelated(_ event: AuditEventSummary) -> Bool {
        let haystack = [
            event.kind,
            event.toolName ?? "",
            event.sessionID ?? "",
            event.detail,
        ].joined(separator: " ").lowercased()
        return [
            "message",
            "reply",
            "chat",
            "discord",
            "telegram",
            "imessage",
            "x ",
            "twitter",
            "agentmail",
            "approval",
        ].contains { haystack.contains($0) }
    }
}

struct DetourHomeInboxItem: Identifiable, Equatable {
    enum Kind: Equatable {
        case incoming
        case reply
        case approval
        case activity

        var label: String {
            switch self {
            case .incoming: "Incoming"
            case .reply: "Reply"
            case .approval: "Needs approval"
            case .activity: "Activity"
            }
        }
    }

    let id: String
    let kind: Kind
    let title: String
    let preview: String
    let source: String
    let createdAt: Date
    let healthy: Bool

    init(message: TranscriptMessage) {
        let kind: Kind = message.role == .assistant ? .reply : message.role == .user ? .incoming : .activity
        self.id = "transcript.\(message.id)"
        self.kind = kind
        self.title = Self.title(for: message.role)
        self.preview = Self.display(message.content)
        self.source = "Default chat"
        self.createdAt = message.createdAt
        self.healthy = true
    }

    init(approval: ApprovalSummary) {
        self.id = "approval.\(approval.id)"
        self.kind = .approval
        self.title = "Review before Detour acts"
        self.preview = Self.display(approval.inputPreview)
        self.source = Self.display("\(approval.toolName) · \(approval.sessionID)")
        self.createdAt = approval.createdAt
        self.healthy = false
    }

    init(event: AuditEventSummary) {
        self.id = "audit.\(event.id)"
        self.kind = .activity
        self.title = Self.display(event.toolName ?? event.kind)
        self.preview = Self.display(event.detail)
        self.source = Self.display(event.sessionID ?? "Agent activity")
        self.createdAt = event.timestamp
        self.healthy = event.success
    }

    private static func title(for role: TranscriptRole) -> String {
        switch role {
        case .assistant: "Detour replied"
        case .user: "You messaged Detour"
        case .tool: "Tool result"
        case .system: "System"
        }
    }

    private static func display(_ value: String) -> String {
        let display = DetourSetupInsightRedaction.display(value)
        return String(display.prefix(220))
    }
}

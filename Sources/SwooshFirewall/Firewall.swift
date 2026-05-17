// SwooshFirewall/Firewall.swift — Agent Firewall (0.4A)
//
// "No invisible autonomy."
// Every durable action is typed, permissioned, replayable, auditable, undoable.

import Foundation
import SwooshTools

// MARK: - Firewall actor

/// Concrete Firewall implementation conforming to the SwooshTools.Firewall protocol.
public actor SwooshFirewallActor: SwooshTools.Firewall {
    private var grantedPermissions: Set<SwooshPermission> = []
    private var deniedPermissions: Set<SwooshPermission> = []

    public init() {}

    public init(
        granted: Set<SwooshPermission> = [],
        denied: Set<SwooshPermission> = []
    ) {
        self.grantedPermissions = granted
        self.deniedPermissions = denied
    }

    public func require(_ permission: SwooshPermission) async throws {
        if deniedPermissions.contains(permission) {
            throw ToolError.denied(permission.rawValue, "Permission \(permission.rawValue) is denied by firewall policy.")
        }
        // If not explicitly granted, also deny
        guard grantedPermissions.contains(permission) else {
            throw ToolError.denied(permission.rawValue, "Permission \(permission.rawValue) has not been granted.")
        }
    }

    public func isGranted(_ permission: SwooshPermission) async -> Bool {
        grantedPermissions.contains(permission) && !deniedPermissions.contains(permission)
    }

    public func grant(_ permission: SwooshPermission) {
        grantedPermissions.insert(permission)
        deniedPermissions.remove(permission)
    }

    public func deny(_ permission: SwooshPermission) {
        deniedPermissions.insert(permission)
        grantedPermissions.remove(permission)
    }

    public func grantAll(_ permissions: Set<SwooshPermission>) {
        grantedPermissions.formUnion(permissions)
        deniedPermissions.subtract(permissions)
    }
}

// MARK: - In-memory audit log

/// Concrete AuditLogging implementation.
public actor SwooshAuditLog: AuditLogging {
    private var entries: [AuditEntry] = []

    public init() {}

    public func append(_ event: AuditEntry) async throws {
        entries.append(event)
    }

    public func tail(limit: Int) async -> [AuditEntry] {
        Array(entries.suffix(limit))
    }

    public func search(query: String, limit: Int) async -> [AuditEntry] {
        let q = query.lowercased()
        return entries.filter { $0.detail.lowercased().contains(q) || ($0.toolName?.lowercased().contains(q) ?? false) }
            .suffix(limit)
            .map { $0 }
    }

    public func getEvent(id: String) async -> AuditEntry? {
        entries.first { $0.id == id }
    }

    public func allEntries() async -> [AuditEntry] {
        entries
    }
}

// MARK: - In-memory approval requester

/// Concrete ApprovalRequesting implementation.
/// In production, this would present UI to the user.
public actor InMemoryApprovalRequester: ApprovalRequesting {
    private var pending: [ToolApprovalRequest] = []
    /// Set to true for testing to auto-approve all requests.
    public var autoApprove: Bool = false

    public init(autoApprove: Bool = false) {
        self.autoApprove = autoApprove
    }

    public func requireApproval(_ request: ToolApprovalRequest) async throws {
        if autoApprove { return }
        pending.append(request)
        // In real implementation, this would wait for user decision
        // For now, it auto-denies pending requests that aren't auto-approved
        throw ToolError.denied(request.toolName, "Approval required but not granted")
    }

    public func listPending() async -> [ToolApprovalRequest] {
        pending
    }

    public func resolve(id: String, decision: ApprovalDecision, reason: String?) async throws {
        pending.removeAll { $0.id == id }
    }
}

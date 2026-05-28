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
    private let persister: (any PermissionPersisting)?

    public init() {
        self.persister = nil
    }

    public init(
        granted: Set<SwooshPermission> = [],
        denied: Set<SwooshPermission> = []
    ) {
        self.grantedPermissions = granted
        self.deniedPermissions = denied
        self.persister = nil
    }

    /// Init with a durable persistence backend. Call `loadPersistedGrants()`
    /// after init to hydrate from disk.
    public init(persister: any PermissionPersisting) {
        self.persister = persister
    }

    /// Load persisted grants from the backing store. Call once at startup.
    public func loadPersistedGrants() async {
        guard let persister else { return }
        do {
            let grants = try await persister.loadGrants()
            for (permission, granted) in grants {
                if granted {
                    grantedPermissions.insert(permission)
                } else {
                    deniedPermissions.insert(permission)
                }
            }
        } catch {
            // Log but don't crash — the firewall defaults to deny-all
        }
    }

    public func require(_ permission: SwooshPermission) async throws {
        if deniedPermissions.contains(permission) {
            throw ToolError.denied(permission.rawValue, "Permission \(permission.rawValue) is denied by firewall policy.")
        }
        guard grantedPermissions.contains(permission) else {
            throw ToolError.denied(permission.rawValue, "Permission \(permission.rawValue) has not been granted.")
        }
    }

    public func isGranted(_ permission: SwooshPermission) async -> Bool {
        grantedPermissions.contains(permission) && !deniedPermissions.contains(permission)
    }

    public func grant(_ permission: SwooshPermission) async {
        grantedPermissions.insert(permission)
        deniedPermissions.remove(permission)
        try? await persister?.saveGrant(permission, granted: true)
    }

    public func deny(_ permission: SwooshPermission) async {
        deniedPermissions.insert(permission)
        grantedPermissions.remove(permission)
        try? await persister?.saveGrant(permission, granted: false)
    }

    public func grantAll(_ permissions: Set<SwooshPermission>) async {
        grantedPermissions.formUnion(permissions)
        deniedPermissions.subtract(permissions)
        for p in permissions {
            try? await persister?.saveGrant(p, granted: true)
        }
    }

    public func listGranted() -> Set<SwooshPermission> {
        grantedPermissions
    }

    public func listDenied() -> Set<SwooshPermission> {
        deniedPermissions
    }

    public func revoke(_ permission: SwooshPermission) async {
        grantedPermissions.remove(permission)
        try? await persister?.removeGrant(permission)
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
        throw ToolError.pendingApproval(request.id)
    }

    public func listPending() async -> [ToolApprovalRequest] {
        pending
    }

    public func resolve(id: String, decision: ApprovalDecision, reason: String?) async throws {
        pending.removeAll { $0.id == id }
    }
}

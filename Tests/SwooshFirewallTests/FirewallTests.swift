// Tests/SwooshFirewallTests/FirewallTests.swift — CRITICAL: permission enforcement
//
// SwooshFirewall is the *only* permission enforcement point in the system
// (per AGENTS.md). These tests verify deny-by-default, explicit grants,
// and that no permission slips through unchecked.

import Testing
import Foundation
@testable import SwooshFirewall
@testable import SwooshTools

// MARK: - Deny-by-default

@Suite("SwooshFirewallActor Deny By Default")
struct FirewallDenyByDefaultTests {

    @Test("Empty firewall denies every permission")
    func emptyDeniesAll() async throws {
        let fw = SwooshFirewallActor()
        for permission in SwooshPermission.allCases {
            await #expect(throws: ToolError.self) {
                try await fw.require(permission)
            }
            let granted = await fw.isGranted(permission)
            #expect(granted == false)
        }
    }

    @Test("Require throws denied error with permission name")
    func deniedErrorContainsName() async {
        let fw = SwooshFirewallActor()
        do {
            try await fw.require(.fileWrite)
            Issue.record("Expected denied error")
        } catch let ToolError.denied(name, message) {
            #expect(name == "fileWrite")
            #expect(message.contains("fileWrite"))
        } catch {
            Issue.record("Wrong error type: \(error)")
        }
    }
}

// MARK: - Grant / deny lifecycle

@Suite("SwooshFirewallActor Grant Lifecycle")
struct FirewallGrantTests {

    @Test("Grant allows previously denied permission")
    func grantAllows() async throws {
        let fw = SwooshFirewallActor()
        await fw.grant(.fileRead)
        try await fw.require(.fileRead)
        #expect(await fw.isGranted(.fileRead))
    }

    @Test("Grant only affects the granted permission")
    func grantIsolated() async throws {
        let fw = SwooshFirewallActor()
        await fw.grant(.fileRead)
        await #expect(throws: ToolError.self) {
            try await fw.require(.fileWrite)
        }
    }

    @Test("Deny revokes a previously granted permission")
    func denyRevokes() async {
        let fw = SwooshFirewallActor()
        await fw.grant(.networkAccess)
        await fw.deny(.networkAccess)

        await #expect(throws: ToolError.self) {
            try await fw.require(.networkAccess)
        }
        #expect(await fw.isGranted(.networkAccess) == false)
    }

    @Test("Grant after deny re-allows")
    func grantAfterDeny() async throws {
        let fw = SwooshFirewallActor()
        await fw.deny(.fileRead)
        await fw.grant(.fileRead)
        try await fw.require(.fileRead)
    }

    @Test("grantAll grants every permission in set")
    func grantAllBatch() async throws {
        let fw = SwooshFirewallActor()
        let batch: Set<SwooshPermission> = [.fileRead, .fileWrite, .networkAccess]
        await fw.grantAll(batch)
        for permission in batch {
            try await fw.require(permission)
        }
    }

    @Test("Credential inheritance permissions deny then grant")
    func credentialInheritancePermissionsRoundTrip() async throws {
        let permissions: [SwooshPermission] = [
            .keychainCredentialsRead,
            .keychainCredentialsImport,
            .browserCookiesRead,
            .browserCookiesImport,
            .messagesRead,
            .accountDelegationRead,
            .accountDelegationWrite,
        ]
        for permission in permissions {
            let fw = SwooshFirewallActor()
            await #expect(throws: ToolError.self) {
                try await fw.require(permission)
            }
            await fw.grant(permission)
            try await fw.require(permission)
        }
    }

    @Test("grantAll removes those permissions from denied set")
    func grantAllClearsDenied() async throws {
        let fw = SwooshFirewallActor()
        await fw.deny(.fileRead)
        await fw.grantAll([.fileRead])
        try await fw.require(.fileRead)
    }
}

// MARK: - Explicit denial precedence

@Suite("SwooshFirewallActor Denial Precedence")
struct FirewallDenialPrecedenceTests {

    @Test("Explicit deny overrides explicit grant")
    func denyOverridesGrant() async {
        // Constructor takes both grant and deny sets;
        // current implementation: deny check runs first.
        let fw = SwooshFirewallActor(
            granted: [.fileRead],
            denied: [.fileRead]
        )
        await #expect(throws: ToolError.self) {
            try await fw.require(.fileRead)
        }
    }

    @Test("Initialized granted permissions work")
    func initializedGrants() async throws {
        let fw = SwooshFirewallActor(granted: [.fileRead, .fileWrite])
        try await fw.require(.fileRead)
        try await fw.require(.fileWrite)
    }
}

// MARK: - SwooshAuditLog

@Suite("SwooshAuditLog")
struct SwooshAuditLogTests {

    private func entry(
        _ kind: AuditEntryKind = .toolCallStarted,
        detail: String = "test event",
        toolName: String? = nil
    ) -> AuditEntry {
        AuditEntry(kind: kind, toolName: toolName, detail: detail)
    }

    @Test("Empty log returns empty arrays")
    func emptyLog() async {
        let log = SwooshAuditLog()
        #expect(await log.allEntries().isEmpty)
        #expect(await log.tail(limit: 10).isEmpty)
        #expect(await log.search(query: "anything", limit: 10).isEmpty)
    }

    @Test("Append adds entry")
    func appendAdds() async throws {
        let log = SwooshAuditLog()
        try await log.append(entry(detail: "hello"))
        let all = await log.allEntries()
        #expect(all.count == 1)
        #expect(all[0].detail == "hello")
    }

    @Test("Tail returns suffix bounded by limit")
    func tailReturnsSuffix() async throws {
        let log = SwooshAuditLog()
        for i in 1...10 {
            try await log.append(entry(detail: "event-\(i)"))
        }
        let tail = await log.tail(limit: 3)
        #expect(tail.count == 3)
        #expect(tail.last?.detail == "event-10")
        #expect(tail.first?.detail == "event-8")
    }

    @Test("Tail with limit larger than total returns all")
    func tailLargerThanTotal() async throws {
        let log = SwooshAuditLog()
        try await log.append(entry(detail: "only"))
        let tail = await log.tail(limit: 100)
        #expect(tail.count == 1)
    }

    @Test("Search matches detail case-insensitively")
    func searchMatchesDetail() async throws {
        let log = SwooshAuditLog()
        try await log.append(entry(detail: "Wrote File X"))
        try await log.append(entry(detail: "Read socket"))
        let hits = await log.search(query: "file", limit: 10)
        #expect(hits.count == 1)
        #expect(hits[0].detail == "Wrote File X")
    }

    @Test("Search matches tool name case-insensitively")
    func searchMatchesToolName() async throws {
        let log = SwooshAuditLog()
        try await log.append(entry(detail: "started", toolName: "git.status"))
        try await log.append(entry(detail: "started", toolName: "files.read"))
        let hits = await log.search(query: "GIT", limit: 10)
        #expect(hits.count == 1)
        #expect(hits[0].toolName == "git.status")
    }

    @Test("Search respects limit")
    func searchRespectsLimit() async throws {
        let log = SwooshAuditLog()
        for i in 1...20 {
            try await log.append(entry(detail: "match-\(i)"))
        }
        let hits = await log.search(query: "match", limit: 5)
        #expect(hits.count == 5)
    }

    @Test("getEvent returns matching entry by id")
    func getEventByID() async throws {
        let log = SwooshAuditLog()
        let target = entry(detail: "find me")
        try await log.append(target)
        try await log.append(entry(detail: "noise"))
        let found = await log.getEvent(id: target.id)
        #expect(found?.detail == "find me")
    }

    @Test("getEvent returns nil for unknown id")
    func getEventMissing() async {
        let log = SwooshAuditLog()
        let found = await log.getEvent(id: "non-existent")
        #expect(found == nil)
    }
}

// MARK: - InMemoryApprovalRequester

@Suite("InMemoryApprovalRequester")
struct InMemoryApprovalRequesterTests {

    private func request(_ id: String = UUID().uuidString) -> ToolApprovalRequest {
        ToolApprovalRequest(
            id: id,
            toolName: "test.tool",
            risk: .medium,
            permission: .toolWrite,
            approvalPolicy: .askEveryTime,
            inputPreview: "preview",
            sessionID: "session-1",
            createdAt: Date()
        )
    }

    @Test("requireApproval throws pendingApproval by default")
    func defaultThrows() async {
        let requester = InMemoryApprovalRequester()
        let req = request()
        do {
            try await requester.requireApproval(req)
            Issue.record("Expected pendingApproval")
        } catch let ToolError.pendingApproval(id) {
            #expect(id == req.id)
        } catch {
            Issue.record("Wrong error: \(error)")
        }
    }

    @Test("Pending request appears in list")
    func pendingListed() async throws {
        let requester = InMemoryApprovalRequester()
        let req = request()
        _ = try? await requester.requireApproval(req)
        let pending = await requester.listPending()
        #expect(pending.count == 1)
        #expect(pending[0].id == req.id)
    }

    @Test("autoApprove bypasses pending state")
    func autoApprove() async throws {
        let requester = InMemoryApprovalRequester(autoApprove: true)
        try await requester.requireApproval(request()) // Should not throw
        let pending = await requester.listPending()
        #expect(pending.isEmpty)
    }

    @Test("Resolve removes pending request")
    func resolveRemoves() async throws {
        let requester = InMemoryApprovalRequester()
        let req = request()
        _ = try? await requester.requireApproval(req)

        try await requester.resolve(id: req.id, decision: .approveOnce, reason: "ok")

        let pending = await requester.listPending()
        #expect(pending.isEmpty)
    }

    @Test("Resolve unknown id is a no-op")
    func resolveUnknownNoOp() async {
        let requester = InMemoryApprovalRequester()
        await #expect(throws: Never.self) {
            try await requester.resolve(id: "nope", decision: .deny, reason: nil)
        }
    }

    @Test("Multiple pending requests tracked separately")
    func multiplePending() async {
        let requester = InMemoryApprovalRequester()
        for _ in 0..<5 {
            _ = try? await requester.requireApproval(request())
        }
        let pending = await requester.listPending()
        #expect(pending.count == 5)
    }
}

// MARK: - Integration: every permission must be explicitly granted

@Suite("Firewall Permission Coverage")
struct FirewallPermissionCoverageTests {

    @Test("Every SwooshPermission denies by default and grants when asked")
    func everyPermissionRoundTrip() async throws {
        for permission in SwooshPermission.allCases {
            let fw = SwooshFirewallActor()
            await #expect(throws: ToolError.self) {
                try await fw.require(permission)
            }
            await fw.grant(permission)
            try await fw.require(permission)
        }
    }
}

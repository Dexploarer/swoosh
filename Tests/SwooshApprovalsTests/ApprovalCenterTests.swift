// Tests/SwooshApprovalsTests/ApprovalCenterTests.swift
// Version: 0.9R
//
// Smoke coverage for the live SwooshApprovals surface:
// InMemoryApprovalStore + ApprovalCenter. End-to-end approval lifecycle
// tests against AgentToolLoop live in SwooshAgentLoopTests.

import Testing
import Foundation
@testable import SwooshApprovals
@testable import SwooshTools

// MARK: - Test audit log

private actor RecordingAuditLog: AuditLogging {
    private var entries: [AuditEntry] = []
    func append(_ event: AuditEntry) async throws { entries.append(event) }
    func tail(limit: Int) async -> [AuditEntry] { Array(entries.suffix(limit)) }
    func search(query: String, limit: Int) async -> [AuditEntry] {
        Array(entries.filter { $0.detail.contains(query) }.prefix(limit))
    }
    func getEvent(id: String) async -> AuditEntry? { entries.first { $0.id == id } }
}

// MARK: - Store

@Suite("Approval store")
struct InMemoryApprovalStoreTests {
    @Test("save then get round-trips the record")
    func saveAndGet() async throws {
        let store = InMemoryApprovalStore()
        let record = ApprovalRecord(
            sessionID: "s1", toolName: "demo", risk: .medium,
            permission: .toolWrite, inputPreview: "preview", origin: .model
        )
        await store.save(record)
        let fetched = await store.get(id: record.id)
        #expect(fetched?.toolName == "demo")
        #expect(fetched?.status == .pending)
    }

    @Test("listPending filters by sessionID and ignores resolved records")
    func listPendingFilters() async throws {
        let store = InMemoryApprovalStore()
        let a = ApprovalRecord(
            sessionID: "s1", toolName: "a", risk: .low,
            permission: .toolWrite, inputPreview: "", origin: .model
        )
        let b = ApprovalRecord(
            sessionID: "s2", toolName: "b", risk: .low,
            permission: .toolWrite, inputPreview: "", origin: .model
        )
        await store.save(a)
        await store.save(b)
        try await store.resolve(id: a.id, status: .approvedOnce, resolvedBy: .human, reason: nil)

        let s1Pending = await store.listPending(sessionID: "s1")
        let s2Pending = await store.listPending(sessionID: "s2")
        #expect(s1Pending.isEmpty)
        #expect(s2Pending.count == 1)
    }

    @Test("resolve rejects double-resolution")
    func doubleResolveThrows() async throws {
        let store = InMemoryApprovalStore()
        let record = ApprovalRecord(
            sessionID: "s1", toolName: "demo", risk: .high,
            permission: .toolWrite, inputPreview: "", origin: .model
        )
        await store.save(record)
        try await store.resolve(id: record.id, status: .approvedOnce, resolvedBy: .human, reason: nil)
        do {
            try await store.resolve(id: record.id, status: .denied, resolvedBy: .human, reason: nil)
            Issue.record("Expected alreadyResolved")
        } catch is ApprovalError {
            // expected
        }
    }

    @Test("approvedForSession matches by tool and session")
    func approvedForSession() async throws {
        let store = InMemoryApprovalStore()
        let record = ApprovalRecord(
            sessionID: "s1", toolName: "demo", risk: .medium,
            permission: .toolWrite, inputPreview: "", origin: .model
        )
        await store.save(record)
        try await store.resolve(id: record.id, status: .approvedForSession, resolvedBy: .human, reason: nil)

        let same = await store.isApprovedForSession(toolName: "demo", sessionID: "s1")
        let other = await store.isApprovedForSession(toolName: "demo", sessionID: "s2")
        let unrelated = await store.isApprovedForSession(toolName: "other", sessionID: "s1")
        #expect(same)
        #expect(!other)
        #expect(!unrelated)
    }
}

// MARK: - Center

@Suite("Approval center")
struct ApprovalCenterTests {
    private func makeCenter() -> (ApprovalCenter, InMemoryApprovalStore, RecordingAuditLog) {
        let store = InMemoryApprovalStore()
        let audit = RecordingAuditLog()
        let center = ApprovalCenter(store: store, audit: audit)
        return (center, store, audit)
    }

    @Test("requireApproval persists a pending record and throws pendingApproval")
    func requireApprovalThrows() async throws {
        let (center, store, _) = makeCenter()
        let request = ToolApprovalRequest(
            id: "a1", toolName: "demo", risk: .high,
            permission: .toolWrite, approvalPolicy: .askEveryTime,
            inputPreview: "preview", sessionID: "s1"
        )

        do {
            try await center.requireApproval(request)
            Issue.record("Expected pendingApproval")
        } catch is ToolError {
            // expected
        }
        let pending = await store.listPending(sessionID: "s1")
        #expect(pending.count == 1)
        #expect(pending.first?.id == "a1")
    }

    @Test("resolveByHuman approves and rejects model origin")
    func resolveByHumanGuardsOrigin() async throws {
        let (center, _, _) = makeCenter()
        let request = ToolApprovalRequest(
            id: "a2", toolName: "demo", risk: .high,
            permission: .toolWrite, approvalPolicy: .askEveryTime,
            inputPreview: "preview", sessionID: "s1"
        )
        _ = try? await center.requireApproval(request)

        do {
            try await center.resolveByHuman(id: "a2", decision: ApprovalDecision.approveOnce, origin: ToolCallOrigin.model)
            Issue.record("Expected modelCannotResolveHumanApproval")
        } catch is ApprovalError {
            // expected
        }
        try await center.resolveByHuman(id: "a2", decision: ApprovalDecision.approveOnce, origin: ToolCallOrigin.human)
        let resolved = await center.getApproval(id: "a2")
        #expect(resolved?.status == .approvedOnce)
    }

    @Test("listPending mirrors the store")
    func listPendingDelegates() async throws {
        let (center, _, _) = makeCenter()
        _ = try? await center.requireApproval(ToolApprovalRequest(
            id: "a3", toolName: "demo", risk: .medium,
            permission: .toolWrite, approvalPolicy: .askEveryTime,
            inputPreview: "p", sessionID: "s1"
        ))
        let pending = await center.listPending()
        #expect(pending.count == 1)
        #expect(pending.first?.toolName == "demo")
    }
}

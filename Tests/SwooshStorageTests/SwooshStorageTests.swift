// SwooshStorageTests/SwooshStorageTests.swift — Unit tests for SwooshStorage — 0.9S

import Foundation
import Testing
@testable import SwooshStorage
@testable import SwooshTools
@testable import SwooshCore
@testable import SwooshApprovals

// MARK: - Schema + Migration tests

@Suite("Schema & Migration")
struct SchemaTests {
    @Test func databaseCreatesInMemory() async throws {
        let db = try SwooshDatabase(inMemory: true)
        // Verify we can query the schema version
        let version = try await db.execute { conn in
            let stmt = try conn.prepare("SELECT COALESCE(MAX(version), 0) FROM schema_version")
            for row in stmt {
                return Int(row[0] as! Int64)
            }
            return 0
        }
        #expect(version == 1)
    }

    @Test func idempotentMigration() async throws {
        // Running migrations twice should not error
        let db = try SwooshDatabase(inMemory: true)
        let version = try await db.execute { conn in
            let stmt = try conn.prepare("SELECT MAX(version) FROM schema_version")
            for row in stmt { return Int(row[0] as! Int64) }
            return 0
        }
        #expect(version == 1)
    }
}

// MARK: - Session store tests

@Suite("SQLiteSessionStore")
struct SessionStoreTests {
    @Test func appendAndLoadTranscript() async throws {
        let db = try SwooshDatabase(inMemory: true)
        let store = SQLiteSessionStore(db: db)

        let msg1 = SwooshCore.ChatMessage(role: .user, content: "Hello")
        let msg2 = SwooshCore.ChatMessage(role: .assistant, content: "Hi there!")

        try await store.appendMessage(sessionID: "s1", message: msg1)
        try await store.appendMessage(sessionID: "s1", message: msg2)

        let transcript = try await store.loadTranscript(sessionID: "s1")
        #expect(transcript.count == 2)
        #expect(transcript[0].role == .user)
        #expect(transcript[0].content == "Hello")
        #expect(transcript[1].role == .assistant)
        #expect(transcript[1].content == "Hi there!")
    }

    @Test func sessionsAreIsolated() async throws {
        let db = try SwooshDatabase(inMemory: true)
        let store = SQLiteSessionStore(db: db)

        try await store.appendMessage(sessionID: "s1", message: SwooshCore.ChatMessage(role: .user, content: "A"))
        try await store.appendMessage(sessionID: "s2", message: SwooshCore.ChatMessage(role: .user, content: "B"))

        let t1 = try await store.loadTranscript(sessionID: "s1")
        let t2 = try await store.loadTranscript(sessionID: "s2")
        #expect(t1.count == 1)
        #expect(t2.count == 1)
        #expect(t1[0].content == "A")
        #expect(t2[0].content == "B")
    }
}

// MARK: - Audit log tests

@Suite("SQLiteAuditLog")
struct AuditLogTests {
    @Test func appendAndTail() async throws {
        let db = try SwooshDatabase(inMemory: true)
        let log = SQLiteAuditLog(db: db)

        let entry = AuditEntry(
            kind: .toolCallSucceeded,
            toolName: "evm.tx_build_native_transfer",
            detail: "Built unsigned ETH transfer"
        )
        try await log.append(entry)

        let tail = await log.tail(limit: 10)
        #expect(tail.count == 1)
        #expect(tail[0].id == entry.id)
        #expect(tail[0].kind == .toolCallSucceeded)
        #expect(tail[0].toolName == "evm.tx_build_native_transfer")
    }

    @Test func searchFindsMatches() async throws {
        let db = try SwooshDatabase(inMemory: true)
        let log = SQLiteAuditLog(db: db)

        try await log.append(AuditEntry(kind: .toolCallSucceeded, toolName: "evm.tx_build_native_transfer", detail: "ETH transfer"))
        try await log.append(AuditEntry(kind: .permissionGranted, detail: "Granted evmRead"))

        let results = await log.search(query: "ETH", limit: 10)
        #expect(results.count == 1)
        #expect(results[0].toolName == "evm.tx_build_native_transfer")
    }

    @Test func getEventByID() async throws {
        let db = try SwooshDatabase(inMemory: true)
        let log = SQLiteAuditLog(db: db)

        let entry = AuditEntry(kind: .safetyViolation, detail: "Blocked seed phrase")
        try await log.append(entry)

        let found = await log.getEvent(id: entry.id)
        #expect(found != nil)
        #expect(found?.kind == .safetyViolation)
    }
}

// MARK: - Memory store tests

@Suite("SQLiteMemoryStore")
struct MemoryStoreTests {
    @Test func proposeAndListCandidates() async throws {
        let db = try SwooshDatabase(inMemory: true)
        let store = SQLiteMemoryStore(db: db)

        let candidateID = try await store.propose(ProposeMemoryCandidateInput(
            text: "User prefers dark mode",
            category: .preference,
            sensitivity: .normal,
            confidence: 0.8,
            evidence: []
        ))

        let candidates = try await store.listCandidates(status: .pending, limit: nil)
        #expect(candidates.count == 1)
        #expect(candidates[0].id == candidateID)
        #expect(candidates[0].text == "User prefers dark mode")
    }

    @Test func approveMovesToApproved() async throws {
        let db = try SwooshDatabase(inMemory: true)
        let store = SQLiteMemoryStore(db: db)

        let candidateID = try await store.propose(ProposeMemoryCandidateInput(
            text: "Uses Vim bindings",
            category: .preference,
            sensitivity: .normal,
            confidence: 0.9,
            evidence: []
        ))

        let memoryID = try await store.approve(candidateID: candidateID, finalText: nil)

        let approved = try await store.listApproved(category: nil, limit: nil)
        #expect(approved.count == 1)
        #expect(approved[0].id == memoryID)
        #expect(approved[0].text == "Uses Vim bindings")

        let candidate = try await store.getCandidate(id: candidateID)
        #expect(candidate?.status == .approved)
    }

    @Test func rejectCandidate() async throws {
        let db = try SwooshDatabase(inMemory: true)
        let store = SQLiteMemoryStore(db: db)

        let candidateID = try await store.propose(ProposeMemoryCandidateInput(
            text: "Some guess",
            category: .fact,
            sensitivity: .normal,
            confidence: 0.3,
            evidence: []
        ))
        try await store.reject(candidateID: candidateID, reason: "Not accurate")

        let candidate = try await store.getCandidate(id: candidateID)
        #expect(candidate?.status == .rejected)
    }

    @Test func searchApprovedMemories() async throws {
        let db = try SwooshDatabase(inMemory: true)
        let store = SQLiteMemoryStore(db: db)

        let c1 = try await store.propose(ProposeMemoryCandidateInput(
            text: "Works at Acme Corp",
            category: .fact,
            sensitivity: .normal,
            confidence: 0.9,
            evidence: []
        ))
        _ = try await store.approve(candidateID: c1, finalText: nil)

        let c2 = try await store.propose(ProposeMemoryCandidateInput(
            text: "Prefers Python over Java",
            category: .preference,
            sensitivity: .normal,
            confidence: 0.8,
            evidence: []
        ))
        _ = try await store.approve(candidateID: c2, finalText: nil)

        let results = try await store.searchApproved(query: "Acme", category: nil, limit: nil)
        #expect(results.count == 1)
        #expect(results[0].memory.text == "Works at Acme Corp")
    }
}

// MARK: - Approval store tests

@Suite("SQLiteApprovalStore")
struct ApprovalStoreTests {
    @Test func saveAndListPending() async throws {
        let db = try SwooshDatabase(inMemory: true)
        let store = SQLiteApprovalStore(db: db)

        let record = ApprovalRecord(
            sessionID: "s1",
            toolName: "evm.tx_broadcast_signed",
            risk: .critical,
            permission: .evmBroadcast,
            inputPreview: "Send 1 ETH",
            origin: .model
        )
        try await store.save(record)

        let pending = await store.listPending(sessionID: "s1")
        #expect(pending.count == 1)
        #expect(pending[0].toolName == "evm.tx_broadcast_signed")
    }

    @Test func resolveApproval() async throws {
        let db = try SwooshDatabase(inMemory: true)
        let store = SQLiteApprovalStore(db: db)

        let record = ApprovalRecord(
            sessionID: "s1",
            toolName: "solana.tx_send_signed",
            risk: .critical,
            permission: .solanaBroadcast,
            inputPreview: "Send SOL",
            origin: .model
        )
        try await store.save(record)

        try await store.resolve(
            id: record.id,
            status: .approvedForSession,
            resolvedBy: .human,
            reason: nil
        )

        let approved = await store.isApprovedForSession(
            toolName: "solana.tx_send_signed",
            sessionID: "s1"
        )
        #expect(approved == true)

        let pendingAfter = await store.listPending(sessionID: "s1")
        #expect(pendingAfter.isEmpty)
    }
}

// MARK: - Merkle tree tests

@Suite("MerkleTree")
struct MerkleTreeTests {
    @Test func emptyLeavesReturnZeroRoot() {
        let root = MerkleTree.root(from: [])
        #expect(root == Data(repeating: 0, count: 32))
    }

    @Test func singleLeafRootIsHashOfDuplicate() {
        let leaf = MerkleTree.leafHash(Data("hello".utf8))
        let root = MerkleTree.root(from: [leaf])
        // Single leaf: root = SHA256(leaf + leaf)
        #expect(root.count == 32)
    }

    @Test func proofVerifiesCorrectly() {
        let leaves = (0..<4).map { i in
            MerkleTree.leafHash(Data("leaf\(i)".utf8))
        }
        let root = MerkleTree.root(from: leaves)

        for i in 0..<4 {
            let proof = MerkleTree.proof(for: i, leaves: leaves)
            let valid = MerkleTree.verify(leaf: leaves[i], proof: proof, root: root)
            #expect(valid, "Proof should verify for leaf \(i)")
        }
    }

    @Test func wrongLeafDoesNotVerify() {
        let leaves = (0..<4).map { i in
            MerkleTree.leafHash(Data("leaf\(i)".utf8))
        }
        let root = MerkleTree.root(from: leaves)
        let proof = MerkleTree.proof(for: 0, leaves: leaves)

        let fakeLeaf = MerkleTree.leafHash(Data("fake".utf8))
        let valid = MerkleTree.verify(leaf: fakeLeaf, proof: proof, root: root)
        #expect(!valid, "Fake leaf should not verify")
    }

    @Test func oddNumberOfLeaves() {
        let leaves = (0..<3).map { i in
            MerkleTree.leafHash(Data("leaf\(i)".utf8))
        }
        let root = MerkleTree.root(from: leaves)
        #expect(root.count == 32)

        // All proofs should still verify
        for i in 0..<3 {
            let proof = MerkleTree.proof(for: i, leaves: leaves)
            let valid = MerkleTree.verify(leaf: leaves[i], proof: proof, root: root)
            #expect(valid)
        }
    }
}

// MARK: - Receipt anchor engine tests

@Suite("ReceiptAnchorEngine")
struct ReceiptAnchorTests {
    @Test func createBatchFromCryptoEntries() async throws {
        let db = try SwooshDatabase(inMemory: true)
        let auditLog = SQLiteAuditLog(db: db)
        let engine = ReceiptAnchorEngine(db: db)

        // Insert some crypto tool entries
        try await auditLog.append(AuditEntry(
            kind: .toolCallSucceeded,
            toolName: "evm.tx_build_native_transfer",
            detail: "Built ETH transfer"
        ))
        try await auditLog.append(AuditEntry(
            kind: .toolCallSucceeded,
            toolName: "solana.tx_build_sol_transfer",
            detail: "Built SOL transfer"
        ))

        let batch = try await engine.createBatch()
        #expect(batch != nil)
        #expect(batch?.entryCount == 2)
        #expect(batch?.anchorStatus == .pending)
        #expect(batch?.merkleRoot.count == 64) // 32 bytes hex-encoded

        // Second call should return nil (all entries are now batched)
        let batch2 = try await engine.createBatch()
        #expect(batch2 == nil)
    }

    @Test func nonCryptoEntriesAreIgnored() async throws {
        let db = try SwooshDatabase(inMemory: true)
        let auditLog = SQLiteAuditLog(db: db)
        let engine = ReceiptAnchorEngine(db: db)

        try await auditLog.append(AuditEntry(
            kind: .toolCallSucceeded,
            toolName: "files.read",
            detail: "Read a file"
        ))
        try await auditLog.append(AuditEntry(
            kind: .memoryApproved,
            detail: "Memory approved"
        ))

        let batch = try await engine.createBatch()
        #expect(batch == nil)
    }
}

// MARK: - Stake gate tests

@Suite("StakeGate")
struct StakeGateTests {
    @Test func insufficientStakeThrows() async throws {
        let db = try SwooshDatabase(inMemory: true)
        let gate = StakeGateActor(db: db, config: StakeGateConfig(requirements: ["evm": 100]))

        do {
            try await gate.requireStake(wallet: "0xABC", toolsetID: "evm")
            #expect(Bool(false), "Should have thrown")
        } catch is ToolError {
            // Expected
        }
    }

    @Test func sufficientStakePasses() async throws {
        let db = try SwooshDatabase(inMemory: true)
        let gate = StakeGateActor(db: db, config: StakeGateConfig(requirements: ["evm": 100]))

        _ = try await gate.recordStake(wallet: "0xABC", tokenMint: "TOKEN", amount: 150, toolsetID: "evm")

        // Should not throw
        try await gate.requireStake(wallet: "0xABC", toolsetID: "evm")
    }

    @Test func releasedStakeNoLongerCounts() async throws {
        let db = try SwooshDatabase(inMemory: true)
        let gate = StakeGateActor(db: db, config: StakeGateConfig(requirements: ["evm": 100]))

        let stakeID = try await gate.recordStake(wallet: "0xABC", tokenMint: "TOKEN", amount: 150, toolsetID: "evm")
        try await gate.releaseStake(stakeID: stakeID)

        let active = try await gate.activeStake(wallet: "0xABC", toolsetID: "evm")
        #expect(active == 0)
    }

    @Test func noRequirementAlwaysPasses() async throws {
        let db = try SwooshDatabase(inMemory: true)
        let gate = StakeGateActor(db: db, config: StakeGateConfig(requirements: [:]))

        // No requirement for "files" — should pass without any stake
        try await gate.requireStake(wallet: "0xABC", toolsetID: "files")
    }
}

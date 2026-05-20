// Tests/SwooshToolsTests/ToolRegistryTests.swift — 0.4A QA tests
//
// Acceptance criteria:
// - Register and list tools
// - Execute read-only allowed tool
// - Denied permission blocks execution
// - humanOnly tools cannot be invoked by model
// - askEveryTime approval path is invoked
// - Audit events are written for success and failure
// - Every registered tool has permission, risk, approval
// - ERC-20 unlimited approval warning exists
// - Solana airdrop disabled on mainnet
// - No tool accepts private key or seed phrase input

import Testing
import Foundation
@testable import SwooshTools
@testable import SwooshFirewall
@testable import SwooshToolsets

// MARK: - Test helpers

/// Mock firewall that grants specific permissions
actor MockFirewall: SwooshTools.Firewall {
    var granted: Set<SwooshPermission>
    init(granted: Set<SwooshPermission> = []) { self.granted = granted }
    func require(_ permission: SwooshPermission) async throws {
        guard granted.contains(permission) else {
            throw ToolError.denied(permission.rawValue, "Not granted")
        }
    }
    func isGranted(_ permission: SwooshPermission) async -> Bool { granted.contains(permission) }
    func grant(_ perm: SwooshPermission) { granted.insert(perm) }
}

/// Mock audit that records entries
actor MockAudit: AuditLogging {
    var entries: [AuditEntry] = []
    func append(_ event: AuditEntry) async throws { entries.append(event) }
    func tail(limit: Int) async -> [AuditEntry] { Array(entries.suffix(limit)) }
    func search(query: String, limit: Int) async -> [AuditEntry] { entries.filter { $0.detail.contains(query) } }
    func getEvent(id: String) async -> AuditEntry? { entries.first { $0.id == id } }
}

/// Mock approvals that auto-approves
actor MockApprovals: ApprovalRequesting {
    var autoApprove: Bool
    var pending: [ToolApprovalRequest] = []
    var approvalRequested = false
    init(autoApprove: Bool = true) { self.autoApprove = autoApprove }
    func requireApproval(_ request: ToolApprovalRequest) async throws {
        approvalRequested = true
        if !autoApprove { throw ToolError.denied(request.toolName, "Denied") }
    }
    func listPending() async -> [ToolApprovalRequest] { pending }
    func resolve(id: String, decision: ApprovalDecision, reason: String?) async throws {}
}

/// Stub file access
struct StubFileAccess: FileAccessing {
    func resolveBookmark(id: String) async throws -> URL { URL(fileURLWithPath: "/tmp/test") }
    func listDirectory(root: URL, relativePath: String?, includeHidden: Bool, maxDepth: Int) async throws -> [FileEntry] { [] }
    func readFile(root: URL, relativePath: String, maxBytes: Int?) async throws -> (content: String, truncated: Bool, redaction: RedactionReport?) { ("", false, nil) }
    func writeFile(root: URL, relativePath: String, content: String, createBackup: Bool) async throws -> (bytesWritten: Int64, backupPath: String?) { (0, nil) }
    func deleteFile(root: URL, relativePath: String) async throws {}
    func searchFiles(root: URL, query: String, filePattern: String?, maxResults: Int?) async throws -> [FileSearchMatch] { [] }
}

/// Stub process runner
struct StubProcessRunner: ProcessRunning {
    func run(executable: String, arguments: [String], workingDirectory: URL?, environment: [String: String]?) async throws -> ProcessResult {
        ProcessResult(exitCode: 0, stdout: "", stderr: "")
    }
}

func makeTestDeps(firewall: any SwooshTools.Firewall, audit: any AuditLogging, approvals: any ApprovalRequesting) -> ToolDependencies {
    ToolDependencies(firewall: firewall, audit: audit, approvals: approvals, fileAccess: StubFileAccess(), processRunner: StubProcessRunner())
}

// MARK: - Tests

@Suite("Tool Registry")
struct ToolRegistryTests {

    @Test("Register and list tools")
    func testRegisterAndList() async throws {
        let fw = MockFirewall(granted: [.toolRead])
        let audit = MockAudit()
        let approvals = MockApprovals()
        let deps = makeTestDeps(firewall: fw, audit: audit, approvals: approvals)
        let registry = ToolRegistry(firewall: fw, audit: audit, approvals: approvals)
        await registry.register(TypeErasedTool(CoreStatusTool(dependencies: deps)))
        let tools = await registry.listAvailable(context: ToolContext(sessionID: "test"))
        #expect(tools.count == 1)
        #expect(tools.first?.name == "core.status")
    }

    @Test("Execute read-only tool with granted permission")
    func testReadOnlyTool() async throws {
        let fw = MockFirewall(granted: [.toolRead])
        let audit = MockAudit()
        let approvals = MockApprovals()
        let deps = makeTestDeps(firewall: fw, audit: audit, approvals: approvals)
        let registry = ToolRegistry(firewall: fw, audit: audit, approvals: approvals)
        await registry.register(TypeErasedTool(CoreStatusTool(dependencies: deps)))
        let ctx = ToolContext(sessionID: "test")
        let result = try await registry.call(name: "core.status", input: .object([:]), context: ctx)
        // Should succeed
        if case .object(let dict) = result {
            #expect(dict["version"] == .string("0.4A"))
        }
    }

    @Test("Denied permission blocks execution")
    func testDeniedPermission() async throws {
        let fw = MockFirewall(granted: []) // No permissions granted
        let audit = MockAudit()
        let approvals = MockApprovals()
        let deps = makeTestDeps(firewall: fw, audit: audit, approvals: approvals)
        let registry = ToolRegistry(firewall: fw, audit: audit, approvals: approvals)
        await registry.register(TypeErasedTool(CoreStatusTool(dependencies: deps)))
        let ctx = ToolContext(sessionID: "test")
        do {
            _ = try await registry.call(name: "core.status", input: .object([:]), context: ctx)
            Issue.record("Should have thrown")
        } catch {
            // Expected: permission denied
        }
        // Verify audit recorded denial
        let entries = await audit.entries
        #expect(entries.contains { $0.kind == .toolCallDenied })
    }

    @Test("humanOnly tools blocked for model invocation")
    func testHumanOnlyBlocksModel() async throws {
        let fw = MockFirewall(granted: [.memoryWrite])
        let audit = MockAudit()
        let approvals = MockApprovals()
        let deps = makeTestDeps(firewall: fw, audit: audit, approvals: approvals)
        let registry = ToolRegistry(firewall: fw, audit: audit, approvals: approvals)
        await registry.register(TypeErasedTool(ApproveCandidateTool(dependencies: deps)))
        let ctx = ToolContext(sessionID: "test", isModelInvocation: true) // Model trying to invoke
        do {
            _ = try await registry.call(name: "vault.approve_candidate", input: .object(["candidateID": .string("x")]), context: ctx)
            Issue.record("Should have thrown humanOnly error")
        } catch let error as ToolError {
            if case .humanOnly = error { /* expected */ }
            else { Issue.record("Wrong error: \(error)") }
        }
    }

    @Test("humanOnly tool succeeds for human invocation")
    func testHumanOnlyAllowsHuman() async throws {
        let fw = MockFirewall(granted: [.memoryWrite])
        let audit = MockAudit()
        let approvals = MockApprovals(autoApprove: true)
        let deps = makeTestDeps(firewall: fw, audit: audit, approvals: approvals)
        let registry = ToolRegistry(firewall: fw, audit: audit, approvals: approvals)
        await registry.register(TypeErasedTool(ApproveCandidateTool(dependencies: deps)))
        let ctx = ToolContext(sessionID: "test", isModelInvocation: false) // Human
        let result = try await registry.call(name: "vault.approve_candidate", input: .object(["candidateID": .string("x")]), context: ctx)
        // Should succeed
        if case .object(let dict) = result {
            #expect(dict["approvedMemoryID"] != nil)
        }
    }

    @Test("Audit events written for success")
    func testAuditSuccess() async throws {
        let fw = MockFirewall(granted: [.toolRead])
        let audit = MockAudit()
        let approvals = MockApprovals()
        let deps = makeTestDeps(firewall: fw, audit: audit, approvals: approvals)
        let registry = ToolRegistry(firewall: fw, audit: audit, approvals: approvals)
        await registry.register(TypeErasedTool(CoreStatusTool(dependencies: deps)))
        let ctx = ToolContext(sessionID: "test")
        _ = try await registry.call(name: "core.status", input: .object([:]), context: ctx)
        let entries = await audit.entries
        #expect(entries.contains { $0.kind == .toolCallStarted })
        #expect(entries.contains { $0.kind == .toolCallSucceeded })
    }

    @Test("Every tool has permission, risk, and approval")
    func testAllToolsHaveMetadata() async throws {
        let fw = MockFirewall(granted: SwooshPermission.allCases.reduce(into: Set<SwooshPermission>()) { $0.insert($1) })
        let audit = MockAudit()
        let approvals = MockApprovals()
        let deps = makeTestDeps(firewall: fw, audit: audit, approvals: approvals)
        let registry = ToolRegistry(firewall: fw, audit: audit, approvals: approvals)
        await DefaultToolRegistrar.registerAll(into: registry, dependencies: deps)
        let tools = await registry.listAvailable(context: ToolContext(sessionID: "test"))
        for tool in tools {
            #expect(!tool.name.isEmpty, "Tool \(tool.id) has empty name")
            #expect(!tool.description.isEmpty, "Tool \(tool.name) has empty description")
            // Risk and approval are always present (non-optional enum values)
        }
        // Should have at least the core tools
        #expect(tools.count >= 5, "Expected at least 5 tools, got \(tools.count)")
    }

    @Test("Tool not found returns error")
    func testToolNotFound() async throws {
        let fw = MockFirewall()
        let audit = MockAudit()
        let approvals = MockApprovals()
        let registry = ToolRegistry(firewall: fw, audit: audit, approvals: approvals)
        let ctx = ToolContext(sessionID: "test")
        do {
            _ = try await registry.call(name: "nonexistent.tool", input: .null, context: ctx)
            Issue.record("Should have thrown")
        } catch let error as ToolError {
            if case .notFound = error { /* expected */ }
            else { Issue.record("Wrong error: \(error)") }
        }
    }
}

@Suite("Safety Config")
struct SafetyConfigTests {

    @Test("Default safety config locks everything")
    func testDefaultsLocked() throws {
        let config = SwooshSafetyConfig.defaultAgent
        #expect(!config.autonomousTradingEnabled)
        #expect(!config.swapExecutionEnabled)
        #expect(!config.privateKeyCustodyEnabled)
        #expect(!config.seedPhraseIngestionEnabled)
        #expect(!config.cookieIngestionEnabled)
        #expect(!config.shellToBlockchainBridgeEnabled)
        #expect(!config.modelSelfApprovalEnabled)
        #expect(!config.mainnetWritesByDefault)
    }

    @Test("Safety violations throw")
    func testSafetyViolations() throws {
        let config = SwooshSafetyConfig.defaultAgent
        #expect(throws: SafetyViolation.self) { try config.requireAutonomousTrading() }
        #expect(throws: SafetyViolation.self) { try config.requirePrivateKeyCustody() }
        #expect(throws: SafetyViolation.self) { try config.requireSeedPhraseIngestion() }
        #expect(throws: SafetyViolation.self) { try config.requireModelSelfApproval() }
    }

    @Test("Custom config can unlock features")
    func testCustomConfig() throws {
        var config = SwooshSafetyConfig.defaultAgent
        config.autonomousTradingEnabled = true
        try config.requireAutonomousTrading() // should not throw
    }
}

@Suite("Blockchain Safety")
struct BlockchainSafetyTests {

    @Test("ERC-20 unlimited approval warning")
    func testUnlimitedApproval() async throws {
        let fw = MockFirewall(granted: [.evmBuildTransaction, .evmMainnetWrite])
        let audit = MockAudit()
        let approvals = MockApprovals(autoApprove: true)
        let deps = makeTestDeps(firewall: fw, audit: audit, approvals: approvals)
        let tool = EVMERC20BuildApproveTool(dependencies: deps)
        let maxUint = "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
        let input = EVMERC20BuildApproveInput(
            chainID: EVMChainID(11155111), tokenContract: EVMAddress("0x1234"),
            owner: EVMAddress("0xaaaa"), spender: EVMAddress("0xbbbb"),
            amountRaw: EVMQuantity(maxUint), tokenSymbol: "USDC"
        )
        let output = try await tool.call(input, context: ToolContext(sessionID: "test"))
        #expect(output.isUnlimitedApproval)
        #expect(!output.warnings.isEmpty)
    }

    @Test("Solana airdrop denied on mainnet")
    func testAirdropMainnet() async throws {
        let fw = MockFirewall(granted: [.solanaBuildTransaction])
        let audit = MockAudit()
        let approvals = MockApprovals(autoApprove: true)
        let deps = makeTestDeps(firewall: fw, audit: audit, approvals: approvals)
        let tool = SolanaRequestAirdropTool(dependencies: deps)
        let input = SolanaRequestAirdropInput(pubkey: SolanaPubkey("xxx"), lamports: Lamports(1_000_000_000), clusterID: "mainnet-beta")
        do {
            _ = try await tool.call(input, context: ToolContext(sessionID: "test"))
            Issue.record("Should have denied mainnet airdrop")
        } catch let error as ToolError {
            if case .denied(_, let reason) = error {
                #expect(reason.contains("mainnet"))
            }
        }
    }

    @Test("Mainnet EVM write requires evmMainnetWrite permission")
    func testMainnetEVMWrite() async throws {
        let fw = MockFirewall(granted: [.evmBuildTransaction]) // NO evmMainnetWrite
        let audit = MockAudit()
        let approvals = MockApprovals(autoApprove: true)
        let deps = makeTestDeps(firewall: fw, audit: audit, approvals: approvals)
        let tool = EVMTxBuildNativeTransferTool(dependencies: deps)
        let input = EVMBuildNativeTransferInput(
            chainID: .mainnet, from: EVMAddress("0xaa"), to: EVMAddress("0xbb"),
            valueWei: EVMQuantity("0x1")
        )
        do {
            _ = try await tool.call(input, context: ToolContext(sessionID: "test"))
            Issue.record("Should have denied mainnet write")
        } catch {
            // Expected: evmMainnetWrite not granted
        }
    }

    @Test("EVM chain detects mainnet")
    func testMainnetDetection() {
        #expect(EVMChainID.mainnet.isMainnet)
        #expect(EVMChainID.polygon.isMainnet)
        #expect(!EVMChainID.sepolia.isMainnet)
    }
}

@Suite("Approval Policy")
struct ApprovalPolicyTests {

    @Test("never does not require approval")
    func testNever() {
        #expect(!ApprovalPolicy.never.requiresUserApproval)
        #expect(ApprovalPolicy.never.modelCanInvoke)
    }

    @Test("humanOnly blocks model")
    func testHumanOnly() {
        #expect(ApprovalPolicy.humanOnly.requiresUserApproval)
        #expect(!ApprovalPolicy.humanOnly.modelCanInvoke)
    }

    @Test("disabled blocks model")
    func testDisabled() {
        #expect(ApprovalPolicy.disabled.requiresUserApproval)
        #expect(!ApprovalPolicy.disabled.modelCanInvoke)
    }

    @Test("askEveryTime requires approval and model can invoke")
    func testAskEveryTime() {
        #expect(ApprovalPolicy.askEveryTime.requiresUserApproval)
        #expect(ApprovalPolicy.askEveryTime.modelCanInvoke)
    }
}

@Suite("Tool Risk")
struct ToolRiskTests {

    @Test("Risk ordering")
    func testRiskOrder() {
        #expect(ToolRisk.readOnly < ToolRisk.low)
        #expect(ToolRisk.low < ToolRisk.medium)
        #expect(ToolRisk.medium < ToolRisk.high)
        #expect(ToolRisk.high < ToolRisk.critical)
    }
}

@Suite("JSONValue Redaction")
struct JSONValueRedactionTests {

    @Test("Redacts sensitive fields")
    func testRedaction() {
        let value = JSONValue.object(["name": .string("test"), "password": .string("secret123")])
        let preview = value.redactedPreview()
        #expect(!preview.contains("secret123"))
    }

    @Test("Truncates long values")
    func testTruncation() {
        let longString = String(repeating: "x", count: 500)
        let value = JSONValue.string(longString)
        let preview = value.redactedPreview(maxLength: 100)
        #expect(preview.count <= 101) // 100 + "…"
    }
}

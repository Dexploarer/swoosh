// Tests/SwooshAgentLoopTests/AgentToolLoopTests.swift — 0.4B Tests
//
// Comprehensive tests for tool-call parser, agent tool loop,
// approval center, and blockchain safety enforcement.

import Testing
import Foundation
@testable import SwooshCore
@testable import SwooshKit
@testable import SwooshTools
@testable import SwooshFirewall
@testable import SwooshApprovals

// Disambiguate duplicate types between SwooshCore and SwooshTools
typealias CoreChatMessage = SwooshCore.ChatMessage
typealias CoreChatRole = SwooshCore.ChatRole

// MARK: - Test doubles

struct MockMemoryLoader: MemoryContextLoading {
    var memories: [(id: String, text: String, category: String)] = []
    func loadApprovedMemories() async throws -> [(id: String, text: String, category: String)] { memories }
}

struct MockReportLoader: SetupReportLoading {
    var report: String? = nil
    func loadLatestSetupReport() async throws -> String? { report }
}

struct MockPermSummarizer: PermissionSummarizing {
    var summary: String = "All permissions granted"
    func permissionSummary() async throws -> String { summary }
}

actor MockSessionStore: SessionStoring {
    var messages: [String: [CoreChatMessage]] = [:]
    func appendMessage(sessionID: String, message: CoreChatMessage) async throws {
        messages[sessionID, default: []].append(message)
    }
    func loadTranscript(sessionID: String) async throws -> [CoreChatMessage] {
        messages[sessionID] ?? []
    }
}

actor MockResponseAuditor: ResponseAuditing {
    var records: [ResponseAuditRecord] = []
    func logResponseAudit(_ audit: ResponseAuditRecord) async throws { records.append(audit) }
    func lastResponseAudit(sessionID: String) async throws -> ResponseAuditRecord? {
        records.last { $0.sessionID == sessionID }
    }
}

/// A model provider that returns a fixed sequence of responses.
actor SequenceModelProvider: ModelProvider {
    nonisolated let providerID = "test"
    nonisolated let modelName = "test-model"
    private var responses: [ModelCompletionResponse]
    private var requests: [ModelCompletionRequest] = []
    private var index = 0

    init(responses: [ModelCompletionResponse]) {
        self.responses = responses
    }

    func complete(_ request: ModelCompletionRequest) async throws -> ModelCompletionResponse {
        requests.append(request)
        guard index < responses.count else {
            return ModelCompletionResponse(content: "No more responses", model: modelName)
        }
        let r = responses[index]
        index += 1
        return r
    }

    func capturedRequests() -> [ModelCompletionRequest] {
        requests
    }
}

/// Grant-all firewall for testing.
actor GrantAllFirewall: SwooshTools.Firewall {
    func require(_ permission: SwooshPermission) async throws {}
    func isGranted(_ permission: SwooshPermission) async -> Bool { true }
}

/// Deny-all firewall for testing.
actor DenyAllFirewall: SwooshTools.Firewall {
    func require(_ permission: SwooshPermission) async throws {
        throw ToolError.denied(permission.rawValue, "Denied by test firewall")
    }
    func isGranted(_ permission: SwooshPermission) async -> Bool { false }
}

/// Passthrough approval (never blocks).
actor PassthroughApproval: ApprovalRequesting {
    func requireApproval(_ request: ToolApprovalRequest) async throws { /* pass */ }
    func listPending() async -> [ToolApprovalRequest] { [] }
    func resolve(id: String, decision: ApprovalDecision, reason: String?) async throws {}
}

/// A simple read-only tool for testing.
struct TestStatusTool: SwooshTool {
    typealias Input = EmptyInput
    typealias Output = StatusOutput

    static let name: ToolName = "core.status"
    static let displayName = "Status"
    static let description = "Returns system status"
    static let permission: SwooshPermission = .deviceProfileRead
    static let risk: ToolRisk = .readOnly
    static let approval: ApprovalPolicy = .never
    static let toolset: ToolsetID = .core

    func call(_ input: Input, context: ToolContext) async throws -> Output {
        StatusOutput(status: "ok")
    }
}
struct EmptyInput: Codable, Sendable {}
struct StatusOutput: Codable, Sendable { let status: String }

/// A humanOnly tool for testing.
struct TestHumanOnlyTool: SwooshTool {
    typealias Input = EmptyInput
    typealias Output = StatusOutput

    static let name: ToolName = "vault.approve_candidate"
    static let displayName = "Approve Candidate"
    static let description = "Approve a memory candidate"
    static let permission: SwooshPermission = .deviceProfileRead
    static let risk: ToolRisk = .medium
    static let approval: ApprovalPolicy = .humanOnly
    static let toolset: ToolsetID = .memory

    func call(_ input: Input, context: ToolContext) async throws -> Output {
        StatusOutput(status: "approved")
    }
}

/// A tool that requires approval.
struct TestApprovalRequiredTool: SwooshTool {
    typealias Input = EmptyInput
    typealias Output = StatusOutput

    static let name: ToolName = "evm.tx_build_native_transfer"
    static let displayName = "Build Native Transfer"
    static let description = "Build an unsigned ETH transfer"
    static let permission: SwooshPermission = .evmRead
    static let risk: ToolRisk = .high
    static let approval: ApprovalPolicy = .askEveryTime
    static let toolset: ToolsetID = .evm

    func call(_ input: Input, context: ToolContext) async throws -> Output {
        StatusOutput(status: "tx_built")
    }
}

// MARK: - Helper to build a registry with test tools

func makeTestRegistry(
    firewall: any SwooshTools.Firewall = GrantAllFirewall(),
    audit: any AuditLogging = SwooshAuditLog(),
    approvals: any ApprovalRequesting = PassthroughApproval(),
    safetyConfig: SwooshSafetyConfig = .defaultAgent
) async -> ToolRegistry {
    let registry = ToolRegistry(firewall: firewall, audit: audit, approvals: approvals, safetyConfig: safetyConfig)
    await registry.register(TypeErasedTool(TestStatusTool()))
    await registry.register(TypeErasedTool(TestHumanOnlyTool()))
    await registry.register(TypeErasedTool(TestApprovalRequiredTool()))
    return registry
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Tool Call Parser Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Tool Call Parser")
struct ToolCallParserTests {

    @Test("Parses native tool call")
    func parsesNativeToolCall() throws {
        let parser = ToolCallParser()
        let response = ModelCompletionResponse(
            content: "",
            model: "test",
            toolCalls: [NativeToolCall(name: "core.status", arguments: .object([:]))]
        )
        let result = try parser.parse(response: response, sessionID: "s1", origin: .model)
        guard case .toolCall(let req) = result else {
            Issue.record("Expected toolCall"); return
        }
        #expect(req.toolName == "core.status")
        #expect(req.origin == .model)
        #expect(req.sessionID == "s1")
    }

    @Test("Parses strict fallback JSON only in tool mode")
    func parsesStrictFallbackInToolMode() throws {
        let parser = ToolCallParser()
        let json = """
        {"swoosh_tool_call":{"name":"memory.list_approved","arguments":{"limit":10}}}
        """
        let response = ModelCompletionResponse(content: json, model: "test", isToolCallMode: true)
        let result = try parser.parse(response: response, sessionID: "s1", origin: .model)
        guard case .toolCall(let req) = result else {
            Issue.record("Expected toolCall"); return
        }
        #expect(req.toolName == "memory.list_approved")
    }

    @Test("Does not parse arbitrary JSON in normal text")
    func doesNotParseArbitraryJSON() throws {
        let parser = ToolCallParser()
        let json = """
        {"swoosh_tool_call":{"name":"core.status","arguments":{}}}
        """
        let response = ModelCompletionResponse(content: json, model: "test", isToolCallMode: false)
        let result = try parser.parse(response: response, sessionID: "s1", origin: .model)
        guard case .assistantText(let text) = result else {
            Issue.record("Expected assistantText"); return
        }
        #expect(text == json)
    }

    @Test("Normal text returns assistantText")
    func normalTextReturnsAssistantText() throws {
        let parser = ToolCallParser()
        let response = ModelCompletionResponse(content: "Hello!", model: "test")
        let result = try parser.parse(response: response, sessionID: "s1", origin: .model)
        guard case .assistantText(let text) = result else {
            Issue.record("Expected assistantText"); return
        }
        #expect(text == "Hello!")
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Tool Registry Execution Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Tool Registry Execution")
struct ToolRegistryExecutionTests {

    @Test("Read-only tool executes without approval")
    func readOnlyToolExecutes() async {
        let registry = await makeTestRegistry()
        let request = ToolExecutionRequest(
            toolName: "core.status", arguments: .object([:]),
            origin: .model, sessionID: "s1"
        )
        let ctx = ToolContext(sessionID: "s1", isModelInvocation: true)
        let result = await registry.execute(request: request, context: ctx)
        #expect(result.status == .succeeded)
        #expect(result.trace != nil)
        #expect(result.trace?.toolName == "core.status")
    }

    @Test("humanOnly tool blocked for model origin")
    func humanOnlyBlockedForModel() async {
        let registry = await makeTestRegistry()
        let request = ToolExecutionRequest(
            toolName: "vault.approve_candidate", arguments: .object([:]),
            origin: .model, sessionID: "s1"
        )
        let ctx = ToolContext(sessionID: "s1", isModelInvocation: true)
        let result = await registry.execute(request: request, context: ctx)
        #expect(result.status == .blockedByPermission)
    }

    @Test("autonomous safety allows model to invoke humanOnly tool")
    func autonomousAllowsHumanOnlyFromModel() async {
        let registry = await makeTestRegistry(safetyConfig: .autonomous)
        let request = ToolExecutionRequest(
            toolName: "vault.approve_candidate", arguments: .object([:]),
            origin: .model, sessionID: "s1"
        )
        let ctx = ToolContext(sessionID: "s1", toolPolicy: .autonomous, isModelInvocation: true)
        let result = await registry.execute(request: request, context: ctx)
        #expect(result.status == .succeeded)
    }

    @Test("humanOnly tool succeeds for human origin")
    func humanOnlySucceedsForHuman() async {
        let registry = await makeTestRegistry()
        let request = ToolExecutionRequest(
            toolName: "vault.approve_candidate", arguments: .object([:]),
            origin: .human, sessionID: "s1"
        )
        let ctx = ToolContext(sessionID: "s1", isModelInvocation: false)
        let result = await registry.execute(request: request, context: ctx)
        #expect(result.status == .succeeded)
    }

    @Test("Denied permission blocks execution")
    func deniedPermissionBlocks() async {
        let registry = await makeTestRegistry(firewall: DenyAllFirewall())
        let request = ToolExecutionRequest(
            toolName: "core.status", arguments: .object([:]),
            origin: .model, sessionID: "s1"
        )
        let ctx = ToolContext(sessionID: "s1", isModelInvocation: true)
        let result = await registry.execute(request: request, context: ctx)
        #expect(result.status == .blockedByPermission)
    }

    @Test("Tool not found returns failed")
    func toolNotFoundFails() async {
        let registry = await makeTestRegistry()
        let request = ToolExecutionRequest(
            toolName: "nonexistent.tool", arguments: .object([:]),
            origin: .model, sessionID: "s1"
        )
        let ctx = ToolContext(sessionID: "s1", isModelInvocation: true)
        let result = await registry.execute(request: request, context: ctx)
        #expect(result.status == .failed)
    }

    @Test("Approval required tool creates pending approval")
    func approvalRequiredCreatesPending() async {
        let approvalCenter = ApprovalCenter(
            store: InMemoryApprovalStore(),
            audit: SwooshAuditLog()
        )
        let registry = await makeTestRegistry(approvals: approvalCenter)
        let request = ToolExecutionRequest(
            toolName: "evm.tx_build_native_transfer", arguments: .object([:]),
            origin: .model, sessionID: "s1"
        )
        let ctx = ToolContext(sessionID: "s1", isModelInvocation: true)
        let result = await registry.execute(request: request, context: ctx)
        #expect(result.status == .pendingApproval)
        #expect(result.approvalID != nil)
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Approval Center Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Approval Center")
struct ApprovalCenterTests {

    @Test("Creates pending approval")
    func createsPendingApproval() async throws {
        let store = InMemoryApprovalStore()
        let center = ApprovalCenter(store: store, audit: SwooshAuditLog())
        let req = ToolApprovalRequest(
            toolName: "evm.tx_build_native_transfer",
            risk: .high,
            inputPreview: "{}",
            sessionID: "s1"
        )
        do {
            try await center.requireApproval(req)
            Issue.record("Should have thrown pendingApproval")
        } catch let error as ToolError {
            guard case .pendingApproval = error else {
                Issue.record("Expected pendingApproval"); return
            }
        }
        let pending = await center.listPending()
        #expect(pending.count == 1)
    }

    @Test("Human can approve")
    func humanCanApprove() async throws {
        let store = InMemoryApprovalStore()
        let center = ApprovalCenter(store: store, audit: SwooshAuditLog())
        let req = ToolApprovalRequest(id: "a1", toolName: "test", risk: .high, inputPreview: "{}", sessionID: "s1")
        _ = try? await center.requireApproval(req)
        try await center.resolveByHuman(id: "a1", decision: .approveOnce, origin: .human)
        let record = await center.getApproval(id: "a1")
        #expect(record?.status == .approvedOnce)
    }

    @Test("Human can deny")
    func humanCanDeny() async throws {
        let store = InMemoryApprovalStore()
        let center = ApprovalCenter(store: store, audit: SwooshAuditLog())
        let req = ToolApprovalRequest(id: "a2", toolName: "test", risk: .high, inputPreview: "{}", sessionID: "s1")
        _ = try? await center.requireApproval(req)
        try await center.resolveByHuman(id: "a2", decision: .deny, origin: .human, reason: "too risky")
        let record = await center.getApproval(id: "a2")
        #expect(record?.status == .denied)
        #expect(record?.denyReason == "too risky")
    }

    @Test("Model cannot approve")
    func modelCannotApprove() async {
        let store = InMemoryApprovalStore()
        let center = ApprovalCenter(store: store, audit: SwooshAuditLog())
        let req = ToolApprovalRequest(id: "a3", toolName: "test", risk: .high, inputPreview: "{}", sessionID: "s1")
        _ = try? await center.requireApproval(req)
        do {
            try await center.resolveByHuman(id: "a3", decision: .approveOnce, origin: .model)
            Issue.record("Should have thrown")
        } catch is ApprovalError {
            // expected
        } catch {
            Issue.record("Wrong error type")
        }
    }

    @Test("Session approval allows subsequent calls")
    func sessionApprovalPersists() async throws {
        let store = InMemoryApprovalStore()
        let center = ApprovalCenter(store: store, audit: SwooshAuditLog())
        let req = ToolApprovalRequest(id: "a4", toolName: "test.tool", risk: .high, approvalPolicy: .askFirstTime, inputPreview: "{}", sessionID: "s1")
        _ = try? await center.requireApproval(req)
        try await center.resolveByHuman(id: "a4", decision: .approveForSession, origin: .human)
        let isApproved = await store.isApprovedForSession(toolName: "test.tool", sessionID: "s1")
        #expect(isApproved == true)
    }

    @Test("Ask every time ignores session approval")
    func askEveryTimeIgnoresSessionApproval() async throws {
        let store = InMemoryApprovalStore()
        let center = ApprovalCenter(store: store, audit: SwooshAuditLog())
        let first = ToolApprovalRequest(id: "a5", toolName: "test.tool", risk: .high, approvalPolicy: .askEveryTime, inputPreview: "{}", sessionID: "s1")
        _ = try? await center.requireApproval(first)
        try await center.resolveByHuman(id: "a5", decision: .approveForSession, origin: .human)
        let second = ToolApprovalRequest(id: "a6", toolName: "test.tool", risk: .high, approvalPolicy: .askEveryTime, inputPreview: "{}", sessionID: "s1")
        do {
            try await center.requireApproval(second)
            Issue.record("askEveryTime should create a new approval")
        } catch let error as ToolError {
            guard case .pendingApproval(let approvalID) = error else {
                Issue.record("Expected pendingApproval"); return
            }
            #expect(approvalID == "a6")
        }
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Agent Tool Loop Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Agent Tool Loop")
struct AgentToolLoopTests {

    @Test("Agent can call read-only tool and continue")
    func agentCallsReadOnlyTool() async throws {
        let registry = await makeTestRegistry()

        // First response: model requests a tool call
        // Second response: model gives final answer
        let provider = SequenceModelProvider(responses: [
            ModelCompletionResponse(
                content: "",
                model: "test-model",
                toolCalls: [NativeToolCall(name: "core.status", arguments: .object([:]))]
            ),
            ModelCompletionResponse(content: "System status is OK.", model: "test-model")
        ])

        let loop = AgentToolLoop(
            memoryLoader: MockMemoryLoader(),
            reportLoader: MockReportLoader(),
            permSummarizer: MockPermSummarizer(),
            sessionStore: MockSessionStore(),
            auditLogger: MockResponseAuditor(),
            modelProvider: provider,
            toolRegistry: registry
        )

        let response = try await loop.run(AgentRequest(input: "What's the status?"))
        #expect(response.message == "System status is OK.")
        #expect(response.toolCallCount == 1)
        #expect(response.toolTracesUsed.count == 1)
        #expect(response.toolTracesUsed[0].status == .succeeded)
    }

    @Test("Agent sends available tool descriptors to provider")
    func sendsAvailableToolDescriptorsToProvider() async throws {
        let registry = await makeTestRegistry()
        let provider = SequenceModelProvider(responses: [
            ModelCompletionResponse(content: "Done.", model: "test-model")
        ])
        let loop = AgentToolLoop(
            memoryLoader: MockMemoryLoader(),
            reportLoader: MockReportLoader(),
            permSummarizer: MockPermSummarizer(),
            sessionStore: MockSessionStore(),
            auditLogger: MockResponseAuditor(),
            modelProvider: provider,
            toolRegistry: registry
        )

        _ = try await loop.run(AgentRequest(input: "check tools"))
        let requests = await provider.capturedRequests()
        #expect(requests.count == 1)
        #expect(requests[0].tools.contains { $0.name == "core.status" })
        #expect(requests[0].tools.contains { $0.name == "evm.tx_build_native_transfer" })
        #expect(!requests[0].tools.contains { $0.name == "vault.approve_candidate" })
    }

    @Test("No-tools policy sends no tools and blocks model tool call")
    func noToolsPolicySendsNoToolsAndBlocksToolCall() async throws {
        let registry = await makeTestRegistry()
        let provider = SequenceModelProvider(responses: [
            ModelCompletionResponse(
                content: "",
                model: "test-model",
                toolCalls: [NativeToolCall(name: "core.status", arguments: .object([:]))]
            )
        ])
        let loop = AgentToolLoop(
            memoryLoader: MockMemoryLoader(),
            reportLoader: MockReportLoader(),
            permSummarizer: MockPermSummarizer(),
            sessionStore: MockSessionStore(),
            auditLogger: MockResponseAuditor(),
            modelProvider: provider,
            toolRegistry: registry,
            policy: .noTools
        )

        let response = try await loop.run(AgentRequest(input: "check tools"))
        let requests = await provider.capturedRequests()
        #expect(requests.first?.tools.isEmpty == true)
        #expect(response.toolCallCount == 0)
        #expect(response.message.contains("disabled"))
    }

    @Test("Swoosh SDK uses tool loop when registry is configured")
    func swooshSDKUsesToolLoopWhenRegistryConfigured() async throws {
        let registry = await makeTestRegistry()
        let provider = SequenceModelProvider(responses: [
            ModelCompletionResponse(
                content: "",
                model: "test-model",
                toolCalls: [NativeToolCall(name: "core.status", arguments: .object([:]))]
            ),
            ModelCompletionResponse(content: "System status is OK.", model: "test-model")
        ])
        let swoosh = try await Swoosh.configure {
            $0.memoryLoader = MockMemoryLoader()
            $0.reportLoader = MockReportLoader()
            $0.permSummarizer = MockPermSummarizer()
            $0.sessionStore = MockSessionStore()
            $0.auditLogger = MockResponseAuditor()
            $0.modelProvider = provider
            $0.toolRegistry = registry
        }

        let response = try await swoosh.ask("status", sessionID: "sdk")
        let requests = await provider.capturedRequests()
        #expect(response.message == "System status is OK.")
        #expect(requests.first?.tools.contains { $0.name == "core.status" } == true)
    }

    @Test("Agent stops at max tool calls")
    func agentStopsAtMaxToolCalls() async throws {
        let registry = await makeTestRegistry()
        // Return tool calls forever
        let responses = (0..<10).map { _ in
            ModelCompletionResponse(
                content: "", model: "test-model",
                toolCalls: [NativeToolCall(name: "core.status", arguments: .object([:]))]
            )
        }
        let provider = SequenceModelProvider(responses: responses)
        let loop = AgentToolLoop(
            memoryLoader: MockMemoryLoader(),
            reportLoader: MockReportLoader(),
            permSummarizer: MockPermSummarizer(),
            sessionStore: MockSessionStore(),
            auditLogger: MockResponseAuditor(),
            modelProvider: provider,
            toolRegistry: registry,
            policy: ToolCallPolicy(maxToolCallsPerTurn: 3)
        )

        let response = try await loop.run(AgentRequest(input: "loop"))
        #expect(response.toolCallCount == 3)
        #expect(response.message.contains("maximum"))
    }

    @Test("Pending approval returns approval message")
    func pendingApprovalReturnsMessage() async throws {
        let approvalCenter = ApprovalCenter(
            store: InMemoryApprovalStore(),
            audit: SwooshAuditLog()
        )
        let registry = await makeTestRegistry(approvals: approvalCenter)

        let provider = SequenceModelProvider(responses: [
            ModelCompletionResponse(
                content: "", model: "test-model",
                toolCalls: [NativeToolCall(name: "evm.tx_build_native_transfer", arguments: .object([:]))]
            )
        ])

        let loop = AgentToolLoop(
            memoryLoader: MockMemoryLoader(),
            reportLoader: MockReportLoader(),
            permSummarizer: MockPermSummarizer(),
            sessionStore: MockSessionStore(),
            auditLogger: MockResponseAuditor(),
            modelProvider: provider,
            toolRegistry: registry
        )

        let response = try await loop.run(AgentRequest(input: "build tx"))
        #expect(response.hasPendingApproval == true)
        #expect(response.message.contains("approval"))
    }

    @Test("/why reports tool calls used")
    func whyReportsToolCalls() async throws {
        let registry = await makeTestRegistry()
        let provider = SequenceModelProvider(responses: [
            ModelCompletionResponse(
                content: "", model: "test-model",
                toolCalls: [NativeToolCall(name: "core.status", arguments: .object([:]))]
            ),
            ModelCompletionResponse(content: "Done.", model: "test-model")
        ])

        let loop = AgentToolLoop(
            memoryLoader: MockMemoryLoader(),
            reportLoader: MockReportLoader(),
            permSummarizer: MockPermSummarizer(),
            sessionStore: MockSessionStore(),
            auditLogger: MockResponseAuditor(),
            modelProvider: provider,
            toolRegistry: registry
        )

        let response = try await loop.run(AgentRequest(input: "check"))
        let why = response.whySummary
        #expect(why.contains("core.status"))
        #expect(why.contains("Tool calls: 1"))
    }

    @Test("Tool result appended to transcript")
    func toolResultAppendedToTranscript() async throws {
        let registry = await makeTestRegistry()
        let sessionStore = MockSessionStore()
        let provider = SequenceModelProvider(responses: [
            ModelCompletionResponse(
                content: "", model: "test-model",
                toolCalls: [NativeToolCall(name: "core.status", arguments: .object([:]))]
            ),
            ModelCompletionResponse(content: "OK.", model: "test-model")
        ])

        let loop = AgentToolLoop(
            memoryLoader: MockMemoryLoader(),
            reportLoader: MockReportLoader(),
            permSummarizer: MockPermSummarizer(),
            sessionStore: sessionStore,
            auditLogger: MockResponseAuditor(),
            modelProvider: provider,
            toolRegistry: registry
        )

        _ = try await loop.run(AgentRequest(input: "check"))
        let messages = await sessionStore.messages["default"] ?? []
        let toolMessages = messages.filter { $0.role == CoreChatRole.tool }
        #expect(toolMessages.count == 1)
        #expect(toolMessages[0].content.contains("succeeded"))
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - ToolCallOrigin Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Tool Call Origin")
struct ToolCallOriginTests {

    @Test("Human can resolve humanOnly approval")
    func humanCanResolve() {
        #expect(ToolCallOrigin.human.canResolveHumanOnlyApproval == true)
    }

    @Test("Model cannot resolve humanOnly approval")
    func modelCannotResolve() {
        #expect(ToolCallOrigin.model.canResolveHumanOnlyApproval == false)
    }

    @Test("Model is model invocation")
    func modelIsModelInvocation() {
        #expect(ToolCallOrigin.model.isModelInvocation == true)
    }

    @Test("Human is not model invocation")
    func humanIsNotModelInvocation() {
        #expect(ToolCallOrigin.human.isModelInvocation == false)
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Tool Call Policy Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Tool Call Policy")
struct ToolCallPolicyTests {

    @Test("Default agent policy allows model tool calls")
    func defaultAllowsModelCalls() {
        let policy = ToolCallPolicy.defaultAgent
        #expect(policy.allowModelToolCalls == true)
        #expect(policy.allowHumanOnlyFromModel == false)
        #expect(policy.maxToolCallsPerTurn == 8)
    }

    @Test("No-tools policy blocks all")
    func noToolsBlocksAll() {
        let policy = ToolCallPolicy.noTools
        #expect(policy.allowModelToolCalls == false)
        #expect(policy.maxToolCallsPerTurn == 0)
    }
}

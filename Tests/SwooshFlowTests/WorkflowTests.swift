// Tests/SwooshFlowTests/WorkflowTests.swift — 0.5A /repeat tests

import Testing
import Foundation
@testable import SwooshFlow
@testable import SwooshTools

// ═══════════════════════════════════════════════════════════════
// MARK: - Test fixtures
// ═══════════════════════════════════════════════════════════════

func makeTestTrace(
    sessionID: String = "test-session",
    toolCalls: [ToolCallTrace] = [],
    memoryIDs: [String] = []
) -> SessionTrace {
    SessionTrace(
        sessionID: sessionID,
        userMessages: [TraceMessage(id: "u1", content: "Inspect this Swift package and run tests")],
        assistantMessages: [TraceMessage(id: "a1", content: String(repeating: "Summary of results with diagnostics and recommendations. ", count: 3))],
        toolCalls: toolCalls,
        memoryIDsUsed: memoryIDs
    )
}

func makeToolTrace(
    name: String, risk: ToolRisk = .readOnly,
    permission: SwooshPermission = .deviceProfileRead,
    approval: ApprovalPolicy = .never
) -> ToolCallTrace {
    ToolCallTrace(
        sessionID: "test-session", requestID: UUID().uuidString,
        toolName: name, origin: .model, risk: risk,
        permission: permission, approvalPolicy: approval,
        status: .succeeded, inputPreview: "{\"rootBookmarkID\": \"root_swoosh\"}"
    )
}

func makeSwiftDevTrace() -> SessionTrace {
    makeTestTrace(toolCalls: [
        makeToolTrace(name: "file.list"),
        makeToolTrace(name: "swift.package_describe", permission: .swiftBuild),
        makeToolTrace(name: "git.status", permission: .gitRead),
        makeToolTrace(name: "swift.test", risk: .medium, permission: .swiftBuild, approval: .askFirstTime),
    ], memoryIDs: ["mem_1"])
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Draft Generation Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Workflow Draft Generator")
struct WorkflowDraftGeneratorTests {
    let generator = DefaultWorkflowDraftGenerator()

    @Test("Generates draft from Swift dev session")
    func generatesDraftFromSwiftSession() async throws {
        let trace = makeSwiftDevTrace()
        let draft = try await generator.generateDraft(from: trace, options: .init())
        #expect(!draft.name.isEmpty)
        #expect(draft.status == .draft)
        #expect(draft.trigger == .manual)
        #expect(draft.steps.count >= 4) // 4 tools + 1 summarize
        #expect(draft.provenance.sourceSessionID == "test-session")
    }

    @Test("Draft defaults to manual trigger")
    func defaultsToManualTrigger() async throws {
        let draft = try await generator.generateDraft(from: makeSwiftDevTrace(), options: .init())
        #expect(draft.trigger == .manual)
    }

    @Test("Draft defaults to draft status")
    func defaultsToDraftStatus() async throws {
        let draft = try await generator.generateDraft(from: makeSwiftDevTrace(), options: .init())
        #expect(draft.status == .draft)
    }

    @Test("Draft contains required permissions")
    func containsPermissions() async throws {
        let draft = try await generator.generateDraft(from: makeSwiftDevTrace(), options: .init())
        let perms = Set(draft.requiredPermissions.map(\.permission))
        #expect(perms.contains(.swiftBuild))
    }

    @Test("Draft detects projectRoot variable")
    func detectsProjectRootVariable() async throws {
        let draft = try await generator.generateDraft(from: makeSwiftDevTrace(), options: .init())
        let varNames = draft.variables.map(\.name)
        #expect(varNames.contains("projectRoot"))
    }

    @Test("Draft computes risk from steps")
    func computesRisk() async throws {
        let draft = try await generator.generateDraft(from: makeSwiftDevTrace(), options: .init())
        #expect(draft.risk >= .medium) // swift.test is medium
    }

    @Test("Write steps excluded by default")
    func writeStepsExcluded() async throws {
        let trace = makeTestTrace(toolCalls: [
            makeToolTrace(name: "file.list"),
            makeToolTrace(name: "file.patch", risk: .high, approval: .askEveryTime),
        ])
        let draft = try await generator.generateDraft(from: trace, options: .init(includeWriteSteps: false))
        let patchSteps = draft.steps.filter { $0.toolName == "file.patch" }
        // Patch should be humanReview, not toolCall
        for step in patchSteps {
            #expect(step.kind == .humanReview)
        }
    }

    @Test("Write steps become approvalGate when included")
    func writeStepsBecomeApprovalGate() async throws {
        let trace = makeTestTrace(toolCalls: [
            makeToolTrace(name: "file.patch", risk: .high, approval: .askEveryTime),
        ])
        let draft = try await generator.generateDraft(from: trace, options: .init(includeWriteSteps: true))
        let patchSteps = draft.steps.filter { $0.toolName == "file.patch" }
        #expect(patchSteps.first?.kind == .approvalGate)
    }

    @Test("EVM broadcast excluded")
    func evmBroadcastExcluded() async throws {
        let trace = makeTestTrace(toolCalls: [
            makeToolTrace(name: "evm.tx_broadcast_signed", risk: .critical),
        ])
        let draft = try await generator.generateDraft(from: trace, options: .init())
        let broadcastSteps = draft.steps.filter { $0.toolName == "evm.tx_broadcast_signed" }
        for step in broadcastSteps {
            #expect(step.kind == .humanReview)
        }
    }

    @Test("Solana send excluded")
    func solanaSendExcluded() async throws {
        let trace = makeTestTrace(toolCalls: [
            makeToolTrace(name: "solana.tx_send_signed", risk: .critical),
        ])
        let draft = try await generator.generateDraft(from: trace, options: .init())
        let sendSteps = draft.steps.filter { $0.toolName == "solana.tx_send_signed" }
        for step in sendSteps {
            #expect(step.kind == .humanReview)
        }
    }

    @Test("Git push excluded")
    func gitPushExcluded() async throws {
        let trace = makeTestTrace(toolCalls: [
            makeToolTrace(name: "git.push", risk: .critical),
        ])
        let draft = try await generator.generateDraft(from: trace, options: .init())
        let pushSteps = draft.steps.filter { $0.toolName == "git.push" }
        for step in pushSteps {
            #expect(step.kind == .humanReview)
        }
    }

    @Test("File delete excluded")
    func fileDeleteExcluded() async throws {
        let trace = makeTestTrace(toolCalls: [
            makeToolTrace(name: "file.delete", risk: .critical),
        ])
        let draft = try await generator.generateDraft(from: trace, options: .init())
        let deleteSteps = draft.steps.filter { $0.toolName == "file.delete" }
        for step in deleteSteps {
            #expect(step.kind == .humanReview)
        }
    }

    @Test("Provenance includes source session")
    func provenanceIncludesSession() async throws {
        let draft = try await generator.generateDraft(from: makeSwiftDevTrace(), options: .init())
        #expect(draft.provenance.sourceSessionID == "test-session")
        #expect(!draft.provenance.sourceToolTraceIDs.isEmpty)
        #expect(draft.provenance.sourceApprovedMemoryIDs == ["mem_1"])
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Validator Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Workflow Validator")
struct WorkflowValidatorTests {
    let generator = DefaultWorkflowDraftGenerator()

    @Test("Valid draft passes validation")
    func validDraftPasses() async throws {
        let draft = try await generator.generateDraft(from: makeSwiftDevTrace(), options: .init())
        let result = WorkflowValidator().validate(draft)
        #expect(result.isValid)
        #expect(result.errors.isEmpty)
    }

    @Test("Empty name fails validation")
    func emptyNameFails() {
        let draft = WorkflowDraft05A(
            name: "", summary: "test", steps: [
                WorkflowStep05A(index: 1, title: "t", kind: .toolCall, toolName: "core.status")
            ], provenance: WorkflowProvenance(sourceSessionID: "s1")
        )
        let result = WorkflowValidator().validate(draft)
        #expect(!result.isValid)
        #expect(result.errors.contains { $0.message.contains("name") })
    }

    @Test("Unknown tool fails with known tools set")
    func unknownToolFails() {
        let draft = WorkflowDraft05A(
            name: "Test", summary: "test", steps: [
                WorkflowStep05A(index: 1, title: "t", kind: .toolCall, toolName: "nonexistent.tool")
            ], provenance: WorkflowProvenance(sourceSessionID: "s1")
        )
        let result = WorkflowValidator(knownTools: ["core.status"]).validate(draft)
        #expect(!result.isValid)
        #expect(result.errors.contains { $0.message.contains("Unknown tool") })
    }

    @Test("Executable humanOnly step fails")
    func executableHumanOnlyFails() {
        let draft = WorkflowDraft05A(
            name: "Test", summary: "test", steps: [
                WorkflowStep05A(index: 1, title: "t", kind: .toolCall, toolName: "vault.approve_candidate")
            ], provenance: WorkflowProvenance(sourceSessionID: "s1")
        )
        let result = WorkflowValidator().validate(draft)
        #expect(!result.isValid)
    }

    @Test("Executable broadcast step fails")
    func executableBroadcastFails() {
        let draft = WorkflowDraft05A(
            name: "Test", summary: "test", steps: [
                WorkflowStep05A(index: 1, title: "t", kind: .toolCall, toolName: "evm.tx_broadcast_signed")
            ], provenance: WorkflowProvenance(sourceSessionID: "s1")
        )
        let result = WorkflowValidator().validate(draft)
        #expect(!result.isValid)
    }

    @Test("Missing provenance fails")
    func missingProvenanceFails() {
        let draft = WorkflowDraft05A(
            name: "Test", summary: "test", steps: [
                WorkflowStep05A(index: 1, title: "t", kind: .note)
            ], provenance: WorkflowProvenance(sourceSessionID: "")
        )
        let result = WorkflowValidator().validate(draft)
        #expect(!result.isValid)
    }

    @Test("Empty steps fails")
    func emptyStepsFails() {
        let draft = WorkflowDraft05A(
            name: "Test", summary: "test",
            provenance: WorkflowProvenance(sourceSessionID: "s1")
        )
        let result = WorkflowValidator().validate(draft)
        #expect(!result.isValid)
    }

    @Test("Placeholder trigger warns")
    func placeholderTriggerWarns() {
        let draft = WorkflowDraft05A(
            name: "Test", summary: "test",
            trigger: .placeholder(WorkflowTriggerPlaceholder(kind: .schedule, humanDescription: "Daily at 8am")),
            steps: [WorkflowStep05A(index: 1, title: "t", kind: .note)],
            provenance: WorkflowProvenance(sourceSessionID: "s1")
        )
        let result = WorkflowValidator().validate(draft)
        #expect(result.isValid)
        #expect(result.warnings.contains { $0.message.contains("placeholder") })
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Storage Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Workflow Draft Store")
struct WorkflowDraftStoreTests {

    @Test("Save and retrieve draft")
    func saveAndRetrieve() async throws {
        let store = InMemoryWorkflowDraftStore()
        let draft = WorkflowDraft05A(
            id: "d1", name: "Test", summary: "test",
            steps: [WorkflowStep05A(index: 1, title: "t", kind: .note)],
            provenance: WorkflowProvenance(sourceSessionID: "s1")
        )
        try await store.saveDraft(draft)
        let retrieved = try await store.getDraft(id: "d1")
        #expect(retrieved?.name == "Test")
    }

    @Test("List drafts")
    func listDrafts() async throws {
        let store = InMemoryWorkflowDraftStore()
        try await store.saveDraft(WorkflowDraft05A(id: "a", name: "A", summary: "a", steps: [WorkflowStep05A(index: 1, title: "t", kind: .note)], provenance: WorkflowProvenance(sourceSessionID: "s")))
        try await store.saveDraft(WorkflowDraft05A(id: "b", name: "B", summary: "b", steps: [WorkflowStep05A(index: 1, title: "t", kind: .note)], provenance: WorkflowProvenance(sourceSessionID: "s")))
        let all = try await store.listDrafts(status: nil)
        #expect(all.count == 2)
    }

    @Test("Delete draft")
    func deleteDraft() async throws {
        let store = InMemoryWorkflowDraftStore()
        try await store.saveDraft(WorkflowDraft05A(id: "d1", name: "T", summary: "t", steps: [WorkflowStep05A(index: 1, title: "t", kind: .note)], provenance: WorkflowProvenance(sourceSessionID: "s")))
        try await store.deleteDraft(id: "d1")
        let result = try await store.getDraft(id: "d1")
        #expect(result == nil)
    }

    @Test("Update draft")
    func updateDraft() async throws {
        let store = InMemoryWorkflowDraftStore()
        var draft = WorkflowDraft05A(id: "d1", name: "Old", summary: "t", steps: [WorkflowStep05A(index: 1, title: "t", kind: .note)], provenance: WorkflowProvenance(sourceSessionID: "s"))
        try await store.saveDraft(draft)
        draft.name = "New"
        try await store.updateDraft(draft)
        let updated = try await store.getDraft(id: "d1")
        #expect(updated?.name == "New")
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Exporter Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Workflow Exporter")
struct WorkflowExporterTests {
    let generator = DefaultWorkflowDraftGenerator()
    let exporter = WorkflowExporter()

    @Test("JSON export round-trips")
    func jsonExportRoundTrips() async throws {
        let draft = try await generator.generateDraft(from: makeSwiftDevTrace(), options: .init())
        let json = try exporter.export(draft, format: .json)
        #expect(json.contains(draft.name))
        #expect(json.contains("draft"))
        // Verify it decodes back
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(WorkflowDraft05A.self, from: json.data(using: .utf8)!)
        #expect(decoded.id == draft.id)
        #expect(decoded.steps.count == draft.steps.count)
    }

    @Test("YAML export contains expected sections")
    func yamlExportContainsSections() async throws {
        let draft = try await generator.generateDraft(from: makeSwiftDevTrace(), options: .init())
        let yaml = try exporter.export(draft, format: .yaml)
        #expect(yaml.contains("name:"))
        #expect(yaml.contains("trigger:"))
        #expect(yaml.contains("steps:"))
        #expect(yaml.contains("provenance:"))
        #expect(yaml.contains("risk:"))
    }

    @Test("Markdown export is human-readable")
    func markdownExportHumanReadable() async throws {
        let draft = try await generator.generateDraft(from: makeSwiftDevTrace(), options: .init())
        let md = try exporter.export(draft, format: .markdown)
        #expect(md.contains("# "))
        #expect(md.contains("## Steps"))
        #expect(md.contains("🔧") || md.contains("🤖"))
        #expect(md.contains("Manual only"))
    }

    @Test("Export does not contain secret content")
    func exportNoSecrets() async throws {
        let draft = try await generator.generateDraft(from: makeSwiftDevTrace(), options: .init())
        let json = try exporter.export(draft, format: .json)
        #expect(!json.contains("API_KEY"))
        #expect(!json.contains("SECRET"))
        #expect(!json.contains("PRIVATE_KEY"))
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Risk Computation Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Workflow Risk")
struct WorkflowRiskTests {

    @Test("Read-only steps produce readOnly risk")
    func readOnlyRisk() {
        let steps = [WorkflowStep05A(index: 1, title: "t", kind: .toolCall, risk: .readOnly)]
        #expect(WorkflowRisk.compute(from: steps) == .readOnly)
    }

    @Test("Medium step raises risk to medium")
    func mediumRisk() {
        let steps = [
            WorkflowStep05A(index: 1, title: "t", kind: .toolCall, risk: .readOnly),
            WorkflowStep05A(index: 2, title: "t", kind: .toolCall, risk: .medium),
        ]
        #expect(WorkflowRisk.compute(from: steps) == .medium)
    }

    @Test("Critical step raises risk to critical")
    func criticalRisk() {
        let steps = [
            WorkflowStep05A(index: 1, title: "t", kind: .toolCall, risk: .readOnly),
            WorkflowStep05A(index: 2, title: "t", kind: .humanReview, risk: .critical),
        ]
        #expect(WorkflowRisk.compute(from: steps) == .critical)
    }

    @Test("Empty steps produce readOnly risk")
    func emptyStepsRisk() {
        #expect(WorkflowRisk.compute(from: []) == .readOnly)
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Draft Model Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Workflow Draft Model")
struct WorkflowDraftModelTests {

    @Test("Draft defaults are safe")
    func defaultsAreSafe() {
        let draft = WorkflowDraft05A(
            name: "Test", summary: "test",
            provenance: WorkflowProvenance(sourceSessionID: "s1")
        )
        #expect(draft.status == .draft)
        #expect(draft.trigger == .manual)
        #expect(draft.steps.isEmpty)
        #expect(draft.risk == .readOnly)
    }

    @Test("Provenance stores source data")
    func provenanceStoresData() {
        let prov = WorkflowProvenance(
            sourceSessionID: "s1",
            sourceToolTraceIDs: ["t1", "t2"],
            sourceApprovedMemoryIDs: ["m1"]
        )
        #expect(prov.sourceSessionID == "s1")
        #expect(prov.sourceToolTraceIDs.count == 2)
        #expect(prov.sourceApprovedMemoryIDs == ["m1"])
    }
}

// Tests/SwooshFlowTests/WorkflowDryRunTests.swift — 0.5B Tests

import Testing
import Foundation
@testable import SwooshFlow
@testable import SwooshTools

// ═══════════════════════════════════════════════════════════════
// MARK: - Test fixtures
// ═══════════════════════════════════════════════════════════════

func makeDraftWithVariables(
    id: String = "test-draft",
    variables: [WorkflowVariable] = [
        WorkflowVariable(name: "projectRoot", type: .approvedRootID, description: "Root"),
        WorkflowVariable(name: "testFilter", type: .string, description: "Filter", required: false),
    ],
    steps: [WorkflowStep05A] = [
        WorkflowStep05A(index: 1, title: "Describe package", kind: .toolCall, toolName: "swift.package_describe", requiredPermissions: [.swiftBuild]),
        WorkflowStep05A(index: 2, title: "Check Git status", kind: .toolCall, toolName: "git.status", requiredPermissions: [.gitRead]),
        WorkflowStep05A(index: 3, title: "Run tests", kind: .toolCall, toolName: "swift.test", requiredPermissions: [.swiftBuild], risk: .medium, approval: .askFirstTime),
    ]
) -> WorkflowDraft05A {
    WorkflowDraft05A(
        id: id, name: "Swift Health Check", summary: "test",
        variables: variables, steps: steps,
        provenance: WorkflowProvenance(sourceSessionID: "s1", sourceToolTraceIDs: ["t1", "t2", "t3"])
    )
}

func makeStoreWithDraft() async -> (InMemoryWorkflowDraftStore, WorkflowDraft05A) {
    let store = InMemoryWorkflowDraftStore()
    let draft = makeDraftWithVariables()
    try! await store.saveDraft(draft)
    return (store, draft)
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Input Resolver Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Input Resolver")
struct InputResolverTests {
    let resolver = DefaultWorkflowInputResolver()

    @Test("Provided input wins over default")
    func providedInputWins() {
        let draft = makeDraftWithVariables(variables: [
            WorkflowVariable(name: "x", type: .string, description: "test", defaultValue: .string("default"))
        ])
        let result = resolver.resolveInputs(draft: draft, providedInputs: ["x": .string("provided")], provenance: nil)
        #expect(result.isComplete)
        #expect(result.resolvedVariables.first?.value == .string("provided"))
        #expect(result.resolvedVariables.first?.source == .providedInput)
    }

    @Test("Default value used when no input")
    func defaultValueUsed() {
        let draft = makeDraftWithVariables(variables: [
            WorkflowVariable(name: "x", type: .string, description: "test", defaultValue: .string("fallback"))
        ])
        let result = resolver.resolveInputs(draft: draft, providedInputs: [:], provenance: nil)
        #expect(result.isComplete)
        #expect(result.resolvedVariables.first?.value == .string("fallback"))
        #expect(result.resolvedVariables.first?.source == .defaultValue)
    }

    @Test("Missing required input creates prompt")
    func missingRequiredCreatesPrompt() {
        let draft = makeDraftWithVariables(variables: [
            WorkflowVariable(name: "projectRoot", type: .approvedRootID, description: "Root")
        ])
        let result = resolver.resolveInputs(draft: draft, providedInputs: [:], provenance: nil)
        #expect(!result.isComplete)
        #expect(result.prompts.count == 1)
        #expect(result.prompts[0].variableName == "projectRoot")
        #expect(result.prompts[0].source == .missingRequiredVariable)
    }

    @Test("Optional unresolved becomes null")
    func optionalBecomesNull() {
        let draft = makeDraftWithVariables(variables: [
            WorkflowVariable(name: "filter", type: .string, description: "opt", required: false)
        ])
        let result = resolver.resolveInputs(draft: draft, providedInputs: [:], provenance: nil)
        #expect(result.isComplete)
        #expect(result.resolvedVariables.first?.value == .null)
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Template Renderer Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Template Renderer")
struct TemplateRendererTests {
    let renderer = DefaultWorkflowTemplateRenderer()

    @Test("Simple variable replacement")
    func simpleReplacement() throws {
        let vars = [ResolvedWorkflowVariable(name: "root", type: .string, value: .string("my_root"), source: .providedInput, isResolved: true)]
        let result = try renderer.render(template: .string("{{root}}"), variables: vars)
        #expect(result == .string("my_root"))
    }

    @Test("Nested JSON template rendering")
    func nestedJsonRendering() throws {
        let vars = [ResolvedWorkflowVariable(name: "root", type: .string, value: .string("r1"), source: .providedInput, isResolved: true)]
        let template = JSONValue.object(["rootID": .string("{{root}}"), "filter": .null])
        let result = try renderer.render(template: template, variables: vars)
        if case .object(let dict) = result {
            #expect(dict["rootID"] == .string("r1"))
            #expect(dict["filter"] == .null)
        } else {
            Issue.record("Expected object")
        }
    }

    @Test("Missing required variable fails")
    func missingRequiredFails() {
        let vars: [ResolvedWorkflowVariable] = []
        #expect(throws: WorkflowDryRunError.self) {
            _ = try renderer.render(template: .string("{{missing}}"), variables: vars)
        }
    }

    @Test("Unknown variable fails")
    func unknownVariableFails() {
        let vars = [ResolvedWorkflowVariable(name: "known", type: .string, value: .string("v"), source: .providedInput, isResolved: true)]
        #expect(throws: WorkflowDryRunError.self) {
            _ = try renderer.render(template: .string("{{unknown}}"), variables: vars)
        }
    }

    @Test("Shell injection blocked")
    func shellInjectionBlocked() {
        let vars: [ResolvedWorkflowVariable] = []
        #expect(throws: WorkflowDryRunError.self) {
            _ = try renderer.render(template: .string("{{ shell(\"rm -rf /\") }}"), variables: vars)
        }
    }

    @Test("Env injection blocked")
    func envInjectionBlocked() {
        let vars: [ResolvedWorkflowVariable] = []
        #expect(throws: WorkflowDryRunError.self) {
            _ = try renderer.render(template: .string("{{ env.SECRET }}"), variables: vars)
        }
    }

    @Test("No template placeholders passes through")
    func noPlaceholdersPassThrough() throws {
        let result = try renderer.render(template: .string("plain text"), variables: [])
        #expect(result == .string("plain text"))
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Permission Planner Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Permission Planner")
struct PermissionPlannerTests {
    let planner = DefaultWorkflowPermissionPlanner()

    @Test("Available permission detected")
    func availablePermission() {
        let plan = WorkflowExecutionPlan(draftID: "d", steps: [
            WorkflowStepPlan(sourceStepID: "s1", index: 1, title: "t", kind: .toolCall, requiredPermissions: [.gitRead])
        ])
        let report = planner.check(plan: plan, permissionStates: [.gitRead: .granted])
        #expect(report.allRequiredPermissionsAvailable)
        #expect(report.requirements.first?.result == .available)
    }

    @Test("Denied permission detected")
    func deniedPermission() {
        let plan = WorkflowExecutionPlan(draftID: "d", steps: [
            WorkflowStepPlan(sourceStepID: "s1", index: 1, title: "t", kind: .toolCall, requiredPermissions: [.gitWrite])
        ])
        let report = planner.check(plan: plan, permissionStates: [.gitWrite: .denied])
        #expect(!report.allRequiredPermissionsAvailable)
        #expect(report.requirements.first?.result == .denied)
    }

    @Test("Missing permission detected")
    func missingPermission() {
        let plan = WorkflowExecutionPlan(draftID: "d", steps: [
            WorkflowStepPlan(sourceStepID: "s1", index: 1, title: "t", kind: .toolCall, requiredPermissions: [.swiftBuild])
        ])
        let report = planner.check(plan: plan, permissionStates: [:])
        #expect(!report.allRequiredPermissionsAvailable)
        #expect(report.requirements.first?.result == .missing)
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Approval Planner Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Approval Planner")
struct ApprovalPlannerTests {
    let planner = DefaultWorkflowApprovalPlanner()

    @Test("Approval required for askEveryTime")
    func approvalRequired() {
        let plan = WorkflowExecutionPlan(draftID: "d", steps: [
            WorkflowStepPlan(sourceStepID: "s1", index: 1, title: "Patch", kind: .toolCall, toolName: "file.patch", approval: .askEveryTime)
        ])
        let report = planner.check(plan: plan)
        #expect(report.humanApprovalRequired)
        #expect(report.requirements.count == 1)
    }

    @Test("Human-only tool detected")
    func humanOnlyDetected() {
        let plan = WorkflowExecutionPlan(draftID: "d", steps: [
            WorkflowStepPlan(sourceStepID: "s1", index: 1, title: "Approve", kind: .toolCall, toolName: "test", approval: .humanOnly)
        ])
        let report = planner.check(plan: plan)
        #expect(report.humanApprovalRequired)
        #expect(report.requirements.first?.approvalPolicy == .humanOnly)
    }

    @Test("No approval for safe tools")
    func noApprovalForSafe() {
        let plan = WorkflowExecutionPlan(draftID: "d", steps: [
            WorkflowStepPlan(sourceStepID: "s1", index: 1, title: "Read", kind: .toolCall, approval: .never)
        ])
        let report = planner.check(plan: plan)
        #expect(!report.humanApprovalRequired)
        #expect(report.requirements.isEmpty)
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Blocked Step Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Blocked Step Detector")
struct BlockedStepDetectorTests {
    let detector = WorkflowBlockedStepDetector()

    @Test("EVM broadcast blocked")
    func evmBroadcastBlocked() {
        let plan = WorkflowExecutionPlan(draftID: "d", steps: [
            WorkflowStepPlan(sourceStepID: "s1", index: 1, title: "Broadcast", kind: .toolCall, toolName: "evm.tx_broadcast_signed")
        ])
        let blocked = detector.detect(plan: plan)
        #expect(blocked.count == 1)
        #expect(blocked[0].reason == .signingOrBroadcast)
    }

    @Test("Solana send blocked")
    func solanaSendBlocked() {
        let plan = WorkflowExecutionPlan(draftID: "d", steps: [
            WorkflowStepPlan(sourceStepID: "s1", index: 1, title: "Send", kind: .toolCall, toolName: "solana.tx_send_signed")
        ])
        let blocked = detector.detect(plan: plan)
        #expect(blocked.count == 1)
        #expect(blocked[0].reason == .signingOrBroadcast)
    }

    @Test("Git push blocked")
    func gitPushBlocked() {
        let plan = WorkflowExecutionPlan(draftID: "d", steps: [
            WorkflowStepPlan(sourceStepID: "s1", index: 1, title: "Push", kind: .toolCall, toolName: "git.push")
        ])
        let blocked = detector.detect(plan: plan)
        #expect(blocked.count == 1)
        #expect(blocked[0].reason == .destructiveTool)
    }

    @Test("Safe tool not blocked")
    func safeToolNotBlocked() {
        let plan = WorkflowExecutionPlan(draftID: "d", steps: [
            WorkflowStepPlan(sourceStepID: "s1", index: 1, title: "Status", kind: .toolCall, toolName: "git.status")
        ])
        let blocked = detector.detect(plan: plan)
        #expect(blocked.isEmpty)
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Cached Replay Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Cached Replay")
struct CachedReplayTests {
    let replay = DefaultWorkflowCachedReplay()

    @Test("Maps by sourceTraceID")
    func mapsBySourceTraceID() {
        let draft = makeDraftWithVariables(steps: [
            WorkflowStep05A(index: 1, title: "Status", kind: .toolCall, toolName: "git.status", sourceTraceID: "trace1"),
        ])
        let traces = [ToolCallTrace(
            id: "trace1", sessionID: "s1", requestID: "r1", toolName: "git.status",
            origin: .model, risk: .readOnly, permission: .gitRead, approvalPolicy: .never,
            status: .succeeded, inputPreview: "{}", outputPreview: "4 files changed"
        )]
        let plan = WorkflowExecutionPlan(draftID: draft.id, steps: [
            WorkflowStepPlan(sourceStepID: draft.steps[0].id, index: 1, title: "Status", kind: .toolCall, toolName: "git.status")
        ])
        let report = replay.replay(draft: draft, plan: plan, sourceTraces: traces)
        #expect(report.mappedSteps.count == 1)
        #expect(report.mappedSteps[0].sourceToolTraceID == "trace1")
        #expect(report.mappedSteps[0].cachedOutputPreview == "4 files changed")
    }

    @Test("Maps by toolName fallback")
    func mapsByToolNameFallback() {
        let draft = makeDraftWithVariables(steps: [
            WorkflowStep05A(index: 1, title: "Status", kind: .toolCall, toolName: "git.status"),
        ])
        let traces = [ToolCallTrace(
            id: "t99", sessionID: "s1", requestID: "r1", toolName: "git.status",
            origin: .model, risk: .readOnly, permission: .gitRead, approvalPolicy: .never,
            status: .succeeded, inputPreview: "{}", outputPreview: "clean"
        )]
        let plan = WorkflowExecutionPlan(draftID: draft.id, steps: [
            WorkflowStepPlan(sourceStepID: draft.steps[0].id, index: 1, title: "Status", kind: .toolCall, toolName: "git.status")
        ])
        let report = replay.replay(draft: draft, plan: plan, sourceTraces: traces)
        #expect(report.mappedSteps.count == 1)
    }

    @Test("Handles missing trace gracefully")
    func handlesMissingTrace() {
        let draft = makeDraftWithVariables(steps: [
            WorkflowStep05A(index: 1, title: "Build", kind: .toolCall, toolName: "swift.build"),
        ])
        let plan = WorkflowExecutionPlan(draftID: draft.id, steps: [
            WorkflowStepPlan(sourceStepID: draft.steps[0].id, index: 1, title: "Build", kind: .toolCall, toolName: "swift.build")
        ])
        let report = replay.replay(draft: draft, plan: plan, sourceTraces: [])
        #expect(report.mappedSteps.isEmpty)
    }

    @Test("Redacts secret-like output")
    func redactsSecrets() {
        let draft = makeDraftWithVariables(steps: [
            WorkflowStep05A(index: 1, title: "Read", kind: .toolCall, toolName: "file.read", sourceTraceID: "t1"),
        ])
        let traces = [ToolCallTrace(
            id: "t1", sessionID: "s1", requestID: "r1", toolName: "file.read",
            origin: .model, risk: .readOnly, permission: .fileRead, approvalPolicy: .never,
            status: .succeeded, inputPreview: "{}", outputPreview: "API_KEY=sk-1234 PASSWORD=hunter2"
        )]
        let plan = WorkflowExecutionPlan(draftID: draft.id, steps: [
            WorkflowStepPlan(sourceStepID: draft.steps[0].id, index: 1, title: "Read", kind: .toolCall, toolName: "file.read")
        ])
        let report = replay.replay(draft: draft, plan: plan, sourceTraces: traces)
        #expect(!report.mappedSteps[0].cachedOutputPreview.contains("API_KEY"))
        #expect(report.mappedSteps[0].cachedOutputPreview.contains("[REDACTED]"))
    }

    @Test("Includes stale warning")
    func includesStaleWarning() {
        let draft = makeDraftWithVariables()
        let plan = WorkflowExecutionPlan(draftID: draft.id)
        let report = replay.replay(draft: draft, plan: plan, sourceTraces: [])
        #expect(report.warning.contains("prior session"))
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Dry-Run Engine Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Dry-Run Engine")
struct DryRunEngineTests {

    @Test("Dry run builds execution plan")
    func buildsExecutionPlan() async throws {
        let (store, draft) = await makeStoreWithDraft()
        let engine = WorkflowDryRunEngine(draftStore: store)
        let report = try await engine.dryRun(WorkflowDryRunRequest(
            draftID: draft.id,
            providedInputs: ["projectRoot": .string("root_swoosh")]
        ))
        #expect(report.plan.steps.count == draft.steps.count)
        #expect(!report.plan.isExecutableInCurrentMilestone)
    }

    @Test("Dry run does not execute tools")
    func doesNotExecuteTools() async throws {
        let (store, draft) = await makeStoreWithDraft()
        let engine = WorkflowDryRunEngine(draftStore: store)
        // If it executed tools, it would crash because there is no real tool registry
        let report = try await engine.dryRun(WorkflowDryRunRequest(draftID: draft.id))
        #expect(report.summaryMarkdown.contains("No tools"))
    }

    @Test("Dry run detects missing inputs")
    func detectsMissingInputs() async throws {
        let (store, draft) = await makeStoreWithDraft()
        let engine = WorkflowDryRunEngine(draftStore: store)
        let report = try await engine.dryRun(WorkflowDryRunRequest(draftID: draft.id))
        // projectRoot is required but not provided
        #expect(!report.unresolvedInputs.isEmpty)
        #expect(report.unresolvedInputs.first?.variableName == "projectRoot")
    }

    @Test("Dry run detects approval requirements")
    func detectsApprovalRequirements() async throws {
        let (store, draft) = await makeStoreWithDraft()
        let engine = WorkflowDryRunEngine(draftStore: store)
        let report = try await engine.dryRun(WorkflowDryRunRequest(
            draftID: draft.id,
            providedInputs: ["projectRoot": .string("root")]
        ))
        #expect(report.approvalReport.humanApprovalRequired)
        #expect(report.approvalReport.requirements.contains { $0.toolName == "swift.test" })
    }

    @Test("Dry run detects missing permissions")
    func detectsMissingPermissions() async throws {
        let (store, draft) = await makeStoreWithDraft()
        let engine = WorkflowDryRunEngine(draftStore: store)
        let report = try await engine.dryRun(WorkflowDryRunRequest(draftID: draft.id))
        #expect(!report.permissionReport.allRequiredPermissionsAvailable)
    }

    @Test("Dry run computes risk")
    func computesRisk() async throws {
        let (store, draft) = await makeStoreWithDraft()
        let engine = WorkflowDryRunEngine(draftStore: store)
        let report = try await engine.dryRun(WorkflowDryRunRequest(draftID: draft.id))
        #expect(report.risk >= .medium)
    }

    @Test("Dry run with draft not found throws")
    func draftNotFoundThrows() async {
        let store = InMemoryWorkflowDraftStore()
        let engine = WorkflowDryRunEngine(draftStore: store)
        do {
            _ = try await engine.dryRun(WorkflowDryRunRequest(draftID: "nonexistent"))
            Issue.record("Should throw")
        } catch is WorkflowDryRunError {
            // expected
        } catch {
            Issue.record("Wrong error: \(error)")
        }
    }

    @Test("Dry run plan is always not executable in 0.5B")
    func planAlwaysNotExecutable() async throws {
        let (store, draft) = await makeStoreWithDraft()
        let engine = WorkflowDryRunEngine(draftStore: store)
        let report = try await engine.dryRun(WorkflowDryRunRequest(draftID: draft.id))
        #expect(report.plan.isExecutableInCurrentMilestone == false)
    }

    @Test("Dry run summary markdown rendered")
    func summaryMarkdownRendered() async throws {
        let (store, draft) = await makeStoreWithDraft()
        let engine = WorkflowDryRunEngine(draftStore: store)
        let report = try await engine.dryRun(WorkflowDryRunRequest(draftID: draft.id))
        #expect(report.summaryMarkdown.contains("Dry Run"))
        #expect(report.summaryMarkdown.contains("Steps"))
        #expect(report.summaryMarkdown.contains("No tools"))
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Blockchain Dry-Run Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Blockchain Dry-Run Safety")
struct BlockchainDryRunTests {

    @Test("EVM signature step blocked")
    func evmSignatureBlocked() {
        let detector = WorkflowBlockedStepDetector()
        let plan = WorkflowExecutionPlan(draftID: "d", steps: [
            WorkflowStepPlan(sourceStepID: "s1", index: 1, title: "Sign", kind: .toolCall, toolName: "evm.tx_request_signature")
        ])
        #expect(!detector.detect(plan: plan).isEmpty)
    }

    @Test("Solana signature step blocked")
    func solanaSignatureBlocked() {
        let detector = WorkflowBlockedStepDetector()
        let plan = WorkflowExecutionPlan(draftID: "d", steps: [
            WorkflowStepPlan(sourceStepID: "s1", index: 1, title: "Sign", kind: .toolCall, toolName: "solana.tx_request_signature")
        ])
        #expect(!detector.detect(plan: plan).isEmpty)
    }

    @Test("Read-only balance step not blocked")
    func balanceStepNotBlocked() {
        let detector = WorkflowBlockedStepDetector()
        let plan = WorkflowExecutionPlan(draftID: "d", steps: [
            WorkflowStepPlan(sourceStepID: "s1", index: 1, title: "Balance", kind: .toolCall, toolName: "evm.account_balance_native")
        ])
        #expect(detector.detect(plan: plan).isEmpty)
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Execution Plan Model Tests
// ═══════════════════════════════════════════════════════════════

@Suite("Execution Plan Model")
struct ExecutionPlanTests {

    @Test("Plan defaults to not executable")
    func planDefaultsNotExecutable() {
        let plan = WorkflowExecutionPlan(draftID: "test")
        #expect(!plan.isExecutableInCurrentMilestone)
    }

    @Test("Step status values are distinct")
    func stepStatusValues() {
        let statuses: Set<WorkflowStepPlanStatus> = [.ready, .missingInput, .permissionMissing, .approvalRequired, .unsupported, .blocked, .disabledInThisMilestone]
        #expect(statuses.count == 7)
    }
}

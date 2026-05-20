// SwooshToolsets/WorkflowTools.swift — Workflow toolset implementations
import Foundation
import SwooshTools

public struct WorkflowDraftFromSessionTool: SwooshTool {
    public typealias Input = WorkflowDraftFromSessionInput; public typealias Output = WorkflowDraftOutput
    public static let name: ToolName = "workflow.draft_from_session"; public static let displayName = "Draft Workflow"
    public static let description = "Create disabled workflow draft"; public static let permission = SwooshPermission.workflowWrite
    public static let risk = ToolRisk.medium; public static let approval = ApprovalPolicy.askEveryTime; public static let toolset = ToolsetID.workflow
    let dependencies: ToolDependencies; public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        let draft = WorkflowDraft(id: UUID().uuidString, name: input.name ?? "Untitled", summary: "Draft from session \(input.sessionID)", steps: [], requiredPermissions: [], enabled: false)
        try await dependencies.workflowStore.saveDraft(draft)
        return WorkflowDraftOutput(draft: draft)
    }
}

public struct WorkflowListDraftsTool: SwooshTool {
    public typealias Input = WorkflowListDraftsInput; public typealias Output = WorkflowListDraftsOutput
    public static let name: ToolName = "workflow.list_drafts"; public static let displayName = "List Drafts"
    public static let description = "List workflow drafts"; public static let permission = SwooshPermission.workflowRead
    public static let risk = ToolRisk.readOnly; public static let approval = ApprovalPolicy.never; public static let toolset = ToolsetID.workflow
    let dependencies: ToolDependencies; public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        WorkflowListDraftsOutput(drafts: try await dependencies.workflowStore.listDrafts())
    }
}

public struct WorkflowGetDraftTool: SwooshTool {
    public typealias Input = WorkflowGetDraftInput; public typealias Output = WorkflowDraftOutput
    public static let name: ToolName = "workflow.get_draft"; public static let displayName = "Get Draft"
    public static let description = "Get workflow draft"; public static let permission = SwooshPermission.workflowRead
    public static let risk = ToolRisk.readOnly; public static let approval = ApprovalPolicy.never; public static let toolset = ToolsetID.workflow
    let dependencies: ToolDependencies; public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        guard let draft = try await dependencies.workflowStore.getDraft(id: input.draftID) else {
            throw ToolError.notFound(input.draftID)
        }
        return WorkflowDraftOutput(draft: draft)
    }
}

public struct WorkflowSaveDraftTool: SwooshTool {
    public typealias Input = WorkflowSaveDraftInput; public typealias Output = WorkflowSaveDraftOutput
    public static let name: ToolName = "workflow.save_draft"; public static let displayName = "Save Draft"
    public static let description = "Save draft"; public static let permission = SwooshPermission.workflowWrite
    public static let risk = ToolRisk.medium; public static let approval = ApprovalPolicy.askEveryTime; public static let toolset = ToolsetID.workflow
    let dependencies: ToolDependencies; public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        try await dependencies.workflowStore.saveDraft(input.draft)
        return WorkflowSaveDraftOutput(draftID: input.draft.id, saved: true)
    }
}

public struct WorkflowEnableTool: SwooshTool {
    public typealias Input = WorkflowEnableInput; public typealias Output = WorkflowEnableOutput
    public static let name: ToolName = "workflow.enable"; public static let displayName = "Enable Workflow"
    public static let description = "Enable workflow"; public static let permission = SwooshPermission.workflowWrite
    public static let risk = ToolRisk.high; public static let approval = ApprovalPolicy.askEveryTime; public static let toolset = ToolsetID.workflow
    let dependencies: ToolDependencies; public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        _ = try await dependencies.workflowStore.setEnabled(id: input.draftID, enabled: input.enabled)
        return WorkflowEnableOutput(draftID: input.draftID, enabled: input.enabled)
    }
}

public struct WorkflowRunDryTool: SwooshTool {
    public typealias Input = WorkflowRunDryInput; public typealias Output = WorkflowRunDryOutput
    public static let name: ToolName = "workflow.run_dry"; public static let displayName = "Dry-Run Workflow"
    public static let description = "Dry-run workflow"; public static let permission = SwooshPermission.workflowRun
    public static let risk = ToolRisk.medium; public static let approval = ApprovalPolicy.askEveryTime; public static let toolset = ToolsetID.workflow
    let dependencies: ToolDependencies; public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        guard let draft = try await dependencies.workflowStore.getDraft(id: input.draftID) else {
            throw ToolError.notFound(input.draftID)
        }
        var warnings: [String] = []
        if draft.steps.isEmpty {
            warnings.append("workflow has no executable steps")
        }
        if draft.steps.contains(where: { $0.toolName?.hasPrefix("workflow.") == true }) {
            warnings.append("workflow tools cannot be nested inside workflow.run")
        }
        if dependencies.workflowStepExecutor == nil, !draft.steps.isEmpty {
            warnings.append("workflow step executor is not configured in this runtime")
        }
        return WorkflowRunDryOutput(
            draftID: input.draftID,
            stepsSimulated: draft.steps.count,
            warnings: warnings,
            wouldRequirePermissions: draft.requiredPermissions
        )
    }
}

public struct WorkflowRunTool: SwooshTool {
    public typealias Input = WorkflowRunInput; public typealias Output = WorkflowRunOutput
    public static let name: ToolName = "workflow.run"; public static let displayName = "Run Workflow"
    public static let description = "Run a saved workflow draft when explicitly confirmed"; public static let permission = SwooshPermission.workflowRun
    public static let risk = ToolRisk.high; public static let approval = ApprovalPolicy.askEveryTime; public static let toolset = ToolsetID.workflow
    let dependencies: ToolDependencies; public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        guard input.confirmExecution else {
            throw ToolError.policyViolation("workflow.run requires confirmExecution=true")
        }
        guard let draft = try await dependencies.workflowStore.getDraft(id: input.draftID) else {
            throw ToolError.notFound(input.draftID)
        }
        guard draft.enabled else {
            throw ToolError.disabled("workflow \(input.draftID) is saved but not enabled")
        }
        guard let executor = dependencies.workflowStepExecutor else {
            throw ToolError.executionFailed("workflow step executor is not configured")
        }

        var completed = 0
        var errors: [String] = []
        for step in draft.steps {
            guard let toolName = step.toolName, !toolName.isEmpty else {
                errors.append("\(step.label): missing toolName")
                continue
            }
            guard !toolName.hasPrefix("workflow.") else {
                errors.append("\(step.label): workflow tools cannot be nested")
                continue
            }
            let result = try await executor.executeWorkflowStep(
                toolName: toolName,
                arguments: step.arguments ?? .object([:]),
                context: ToolContext(sessionID: context.sessionID, isModelInvocation: false)
            )
            if result.status == .succeeded {
                completed += 1
            } else {
                errors.append("\(step.label): \(result.errorMessage ?? result.status.rawValue)")
            }
        }
        let status = errors.isEmpty ? "completed" : (completed == 0 ? "failed" : "completed_with_errors")
        return WorkflowRunOutput(
            runID: UUID().uuidString,
            status: status,
            stepsCompleted: completed,
            errors: errors
        )
    }
}

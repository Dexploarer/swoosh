// SwooshToolsets/WorkflowTools.swift — Workflow toolset implementations
// workflow.run is typed but disabled in 0.4A.
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
        return WorkflowDraftOutput(draft: draft)
    }
}

public struct WorkflowListDraftsTool: SwooshTool {
    public typealias Input = WorkflowListDraftsInput; public typealias Output = WorkflowListDraftsOutput
    public static let name: ToolName = "workflow.list_drafts"; public static let displayName = "List Drafts"
    public static let description = "List workflow drafts"; public static let permission = SwooshPermission.workflowRead
    public static let risk = ToolRisk.readOnly; public static let approval = ApprovalPolicy.never; public static let toolset = ToolsetID.workflow
    let dependencies: ToolDependencies; public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output { WorkflowListDraftsOutput(drafts: []) }
}

public struct WorkflowGetDraftTool: SwooshTool {
    public typealias Input = WorkflowGetDraftInput; public typealias Output = WorkflowDraftOutput
    public static let name: ToolName = "workflow.get_draft"; public static let displayName = "Get Draft"
    public static let description = "Get workflow draft"; public static let permission = SwooshPermission.workflowRead
    public static let risk = ToolRisk.readOnly; public static let approval = ApprovalPolicy.never; public static let toolset = ToolsetID.workflow
    let dependencies: ToolDependencies; public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        let draft = WorkflowDraft(id: input.draftID, name: "", summary: "", steps: [], requiredPermissions: [], enabled: false)
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
        WorkflowSaveDraftOutput(draftID: input.draft.id, saved: true)
    }
}

public struct WorkflowEnableTool: SwooshTool {
    public typealias Input = WorkflowEnableInput; public typealias Output = WorkflowEnableOutput
    public static let name: ToolName = "workflow.enable"; public static let displayName = "Enable Workflow"
    public static let description = "Enable workflow"; public static let permission = SwooshPermission.workflowWrite
    public static let risk = ToolRisk.high; public static let approval = ApprovalPolicy.askEveryTime; public static let toolset = ToolsetID.workflow
    let dependencies: ToolDependencies; public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        WorkflowEnableOutput(draftID: input.draftID, enabled: input.enabled)
    }
}

public struct WorkflowRunDryTool: SwooshTool {
    public typealias Input = WorkflowRunDryInput; public typealias Output = WorkflowRunDryOutput
    public static let name: ToolName = "workflow.run_dry"; public static let displayName = "Dry-Run Workflow"
    public static let description = "Dry-run workflow"; public static let permission = SwooshPermission.workflowRun
    public static let risk = ToolRisk.medium; public static let approval = ApprovalPolicy.askEveryTime; public static let toolset = ToolsetID.workflow
    let dependencies: ToolDependencies; public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        WorkflowRunDryOutput(draftID: input.draftID, stepsSimulated: 0, warnings: [], wouldRequirePermissions: [])
    }
}

public struct WorkflowRunTool: SwooshTool {
    public typealias Input = WorkflowRunInput; public typealias Output = WorkflowRunOutput
    public static let name: ToolName = "workflow.run"; public static let displayName = "Run Workflow"
    public static let description = "Execute workflow (disabled in 0.4A)"; public static let permission = SwooshPermission.workflowRun
    public static let risk = ToolRisk.high; public static let approval = ApprovalPolicy.disabled; public static let toolset = ToolsetID.workflow
    let dependencies: ToolDependencies; public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        throw ToolError.disabled("workflow.run is disabled in 0.4A. Execution waits for 0.5A.")
    }
}

// SwooshToolsets/PermissionTools.swift — Permissions & Approval toolset
import Foundation
import SwooshTools

public struct PermissionSummaryTool: SwooshTool {
    public typealias Input = PermissionSummaryInput; public typealias Output = PermissionSummaryOutput
    public static let name: ToolName = "permissions.summary"; public static let displayName = "Permission Summary"
    public static let description = "Show permission summary"; public static let permission = SwooshPermission.toolRead
    public static let risk = ToolRisk.readOnly; public static let approval = ApprovalPolicy.never; public static let toolset = ToolsetID.permissions
    let dependencies: ToolDependencies; public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        PermissionSummaryOutput(permissions: [], markdown: "No permissions configured.")
    }
}

public struct PermissionGetTool: SwooshTool {
    public typealias Input = PermissionGetInput; public typealias Output = PermissionGetOutput
    public static let name: ToolName = "permissions.get"; public static let displayName = "Get Permission"
    public static let description = "Get one permission state"; public static let permission = SwooshPermission.toolRead
    public static let risk = ToolRisk.readOnly; public static let approval = ApprovalPolicy.never; public static let toolset = ToolsetID.permissions
    let dependencies: ToolDependencies; public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        PermissionGetOutput(entry: PermissionEntry(permission: input.permission, state: .notRequested))
    }
}

public struct PermissionRequestTool: SwooshTool {
    public typealias Input = PermissionRequestInput; public typealias Output = PermissionRequestOutput
    public static let name: ToolName = "permissions.request"; public static let displayName = "Request Permission"
    public static let description = "Request permission from user"; public static let permission = SwooshPermission.approvalResolve
    public static let risk = ToolRisk.medium; public static let approval = ApprovalPolicy.humanOnly; public static let toolset = ToolsetID.permissions
    let dependencies: ToolDependencies; public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        PermissionRequestOutput(requestID: UUID().uuidString, state: .pending)
    }
}

public struct ListPendingApprovalsTool: SwooshTool {
    public typealias Input = ListPendingApprovalsInput; public typealias Output = ListPendingApprovalsOutput
    public static let name: ToolName = "approvals.list_pending"; public static let displayName = "List Pending Approvals"
    public static let description = "List pending approvals"; public static let permission = SwooshPermission.approvalResolve
    public static let risk = ToolRisk.readOnly; public static let approval = ApprovalPolicy.never; public static let toolset = ToolsetID.permissions
    let dependencies: ToolDependencies; public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        let pending = await dependencies.approvals.listPending()
        return ListPendingApprovalsOutput(approvals: pending)
    }
}

public struct ResolveApprovalTool: SwooshTool {
    public typealias Input = ResolveApprovalInput; public typealias Output = ResolveApprovalOutput
    public static let name: ToolName = "approvals.resolve"; public static let displayName = "Resolve Approval"
    public static let description = "Approve/deny pending tool call"; public static let permission = SwooshPermission.approvalResolve
    public static let risk = ToolRisk.high; public static let approval = ApprovalPolicy.humanOnly; public static let toolset = ToolsetID.permissions
    let dependencies: ToolDependencies; public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        try await dependencies.approvals.resolve(id: input.approvalID, decision: input.decision, reason: input.reason)
        return ResolveApprovalOutput(approvalID: input.approvalID, resolved: true)
    }
}

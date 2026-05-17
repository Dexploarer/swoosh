// SwooshToolsets/AuditTools.swift — Audit toolset implementations
import Foundation
import SwooshTools

public struct AuditTailTool: SwooshTool {
    public typealias Input = AuditTailInput; public typealias Output = AuditTailOutput
    public static let name: ToolName = "audit.tail"; public static let displayName = "Audit Tail"
    public static let description = "Read recent audit events"; public static let permission = SwooshPermission.auditRead
    public static let risk = ToolRisk.readOnly; public static let approval = ApprovalPolicy.never; public static let toolset = ToolsetID.audit
    let dependencies: ToolDependencies; public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        let events = await dependencies.audit.tail(limit: input.limit ?? 50)
        return AuditTailOutput(events: events)
    }
}

public struct AuditSearchTool: SwooshTool {
    public typealias Input = AuditSearchInput; public typealias Output = AuditSearchOutput
    public static let name: ToolName = "audit.search"; public static let displayName = "Audit Search"
    public static let description = "Search audit timeline"; public static let permission = SwooshPermission.auditRead
    public static let risk = ToolRisk.readOnly; public static let approval = ApprovalPolicy.never; public static let toolset = ToolsetID.audit
    let dependencies: ToolDependencies; public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        let events = await dependencies.audit.search(query: input.query, limit: input.limit ?? 50)
        return AuditSearchOutput(events: events)
    }
}

public struct AuditGetEventTool: SwooshTool {
    public typealias Input = AuditGetEventInput; public typealias Output = AuditGetEventOutput
    public static let name: ToolName = "audit.get_event"; public static let displayName = "Get Audit Event"
    public static let description = "Get one audit event"; public static let permission = SwooshPermission.auditRead
    public static let risk = ToolRisk.readOnly; public static let approval = ApprovalPolicy.never; public static let toolset = ToolsetID.audit
    let dependencies: ToolDependencies; public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        let event = await dependencies.audit.getEvent(id: input.eventID)
        return AuditGetEventOutput(event: event)
    }
}

// SwooshToolsets/CoreTools.swift — Core toolset implementations
import Foundation
import SwooshTools

// ── core.status ───────────────────────────────────────────────────
public struct CoreStatusTool: SwooshTool {
    public typealias Input = CoreStatusInput
    public typealias Output = CoreStatusOutput
    public static let name: ToolName = "core.status"
    public static let displayName = "Runtime Status"
    public static let description = "Show Swoosh runtime status"
    public static let permission = SwooshPermission.toolRead
    public static let risk = ToolRisk.readOnly
    public static let approval = ApprovalPolicy.never
    public static let toolset = ToolsetID.core
    let dependencies: ToolDependencies
    public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        CoreStatusOutput(version: "0.4A", mode: "agent", statePlane: "active",
                         approvedMemoryCount: 0, pendingMemoryCandidateCount: 0,
                         enabledToolsets: ToolsetID.allCases.map(\.rawValue))
    }
}

// ── core.explain_context ──────────────────────────────────────────
public struct ExplainContextTool: SwooshTool {
    public typealias Input = ExplainContextInput
    public typealias Output = ExplainContextOutput
    public static let name: ToolName = "core.explain_context"
    public static let displayName = "Explain Context"
    public static let description = "Explain context used in latest response"
    public static let permission = SwooshPermission.toolRead
    public static let risk = ToolRisk.readOnly
    public static let approval = ApprovalPolicy.never
    public static let toolset = ToolsetID.core
    let dependencies: ToolDependencies
    public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        ExplainContextOutput(approvedMemoryIDs: [], setupReportID: nil,
                             permissionSummary: "No permissions loaded",
                             excludedSources: ["rejected_candidates", "raw_scout_records", "cookies", "secrets"],
                             modelUsed: nil)
    }
}

// ── core.list_toolsets ────────────────────────────────────────────
public struct ListToolsetsTool: SwooshTool {
    public typealias Input = ListToolsetsInput
    public typealias Output = ListToolsetsOutput
    public static let name: ToolName = "core.list_toolsets"
    public static let displayName = "List Toolsets"
    public static let description = "List enabled toolsets"
    public static let permission = SwooshPermission.toolRead
    public static let risk = ToolRisk.readOnly
    public static let approval = ApprovalPolicy.never
    public static let toolset = ToolsetID.core
    let dependencies: ToolDependencies
    public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        ListToolsetsOutput(toolsets: ToolsetID.allCases.map(\.rawValue))
    }
}

// ── core.list_tools ───────────────────────────────────────────────
public struct ListToolsTool: SwooshTool {
    public typealias Input = ListToolsInput
    public typealias Output = ListToolsOutput
    public static let name: ToolName = "core.list_tools"
    public static let displayName = "List Tools"
    public static let description = "List available tools"
    public static let permission = SwooshPermission.toolRead
    public static let risk = ToolRisk.readOnly
    public static let approval = ApprovalPolicy.never
    public static let toolset = ToolsetID.core
    let dependencies: ToolDependencies
    let registry: ToolRegistry?
    public init(dependencies: ToolDependencies, registry: ToolRegistry? = nil) {
        self.dependencies = dependencies
        self.registry = registry
    }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        let tools = await registry?.listAvailable(context: context) ?? []
        let filtered = input.toolset.map { toolset in
            tools.filter { $0.toolset.rawValue == toolset }
        } ?? tools
        return ListToolsOutput(tools: filtered)
    }
}

// ── core.get_tool_schema ──────────────────────────────────────────
public struct GetToolSchemaTool: SwooshTool {
    public typealias Input = GetToolSchemaInput
    public typealias Output = GetToolSchemaOutput
    public static let name: ToolName = "core.get_tool_schema"
    public static let displayName = "Get Tool Schema"
    public static let description = "Return schema for a tool"
    public static let permission = SwooshPermission.toolRead
    public static let risk = ToolRisk.readOnly
    public static let approval = ApprovalPolicy.never
    public static let toolset = ToolsetID.core
    let dependencies: ToolDependencies
    let registry: ToolRegistry?
    public init(dependencies: ToolDependencies, registry: ToolRegistry? = nil) {
        self.dependencies = dependencies
        self.registry = registry
    }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        GetToolSchemaOutput(descriptor: await registry?.getToolSchema(name: ToolName(input.toolName)))
    }
}

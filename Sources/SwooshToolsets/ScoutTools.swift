// SwooshToolsets/ScoutTools.swift — Scout toolset implementations
import Foundation
import SwooshTools

public struct ScoutListSourcesTool: SwooshTool {
    public typealias Input = ScoutListSourcesInput; public typealias Output = ScoutListSourcesOutput
    public static let name: ToolName = "scout.list_sources"; public static let displayName = "List Scout Sources"
    public static let description = "List Scout sources"; public static let permission = SwooshPermission.toolRead
    public static let risk = ToolRisk.readOnly; public static let approval = ApprovalPolicy.never; public static let toolset = ToolsetID.scout
    let dependencies: ToolDependencies; public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output { ScoutListSourcesOutput(sources: []) }
}

public struct ScoutStatusTool: SwooshTool {
    public typealias Input = ScoutStatusInput; public typealias Output = ScoutStatusOutput
    public static let name: ToolName = "scout.status"; public static let displayName = "Scout Status"
    public static let description = "Show latest scan status"; public static let permission = SwooshPermission.toolRead
    public static let risk = ToolRisk.readOnly; public static let approval = ApprovalPolicy.never; public static let toolset = ToolsetID.scout
    let dependencies: ToolDependencies; public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        ScoutStatusOutput(lastScanDate: nil, recordCount: 0, candidateCount: 0)
    }
}

public struct ScoutRunTool: SwooshTool {
    public typealias Input = ScoutRunInput; public typealias Output = ScoutRunOutput
    public static let name: ToolName = "scout.run"; public static let displayName = "Run Scout Scan"
    public static let description = "Run approved Scout scan"; public static let permission = SwooshPermission.toolWrite
    public static let risk = ToolRisk.medium; public static let approval = ApprovalPolicy.askEveryTime; public static let toolset = ToolsetID.scout
    let dependencies: ToolDependencies; public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        ScoutRunOutput(scanID: UUID().uuidString, recordsCreated: 0, candidatesCreated: 0, skippedSources: [])
    }
}

public struct ScoutGetReportTool: SwooshTool {
    public typealias Input = ScoutGetReportInput; public typealias Output = ScoutGetReportOutput
    public static let name: ToolName = "scout.get_report"; public static let displayName = "Get Scout Report"
    public static let description = "Return latest Scout report"; public static let permission = SwooshPermission.toolRead
    public static let risk = ToolRisk.readOnly; public static let approval = ApprovalPolicy.never; public static let toolset = ToolsetID.scout
    let dependencies: ToolDependencies; public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        ScoutGetReportOutput(reportMarkdown: "No scan data available.", scanID: input.scanID)
    }
}

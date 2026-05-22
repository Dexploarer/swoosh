// SwooshToolsets/LaunchpadTools.swift — Launchpad platform catalog tools
import Foundation
import SwooshClient
import SwooshTools

public struct LaunchpadListPlatformsInput: Codable, Sendable {
    public init() {}
}

public struct LaunchpadGetPlatformInput: Codable, Sendable {
    public let id: String

    public init(id: String) {
        self.id = id
    }
}

public struct LaunchpadListPlatformsTool: SwooshTool {
    public typealias Input = LaunchpadListPlatformsInput
    public typealias Output = LaunchpadsResponse

    public static let name: ToolName = "launchpad.list_platforms"
    public static let displayName = "Launchpad Platform Catalog"
    public static let description = "List launchpad platform coverage, chain support, docs, skill, and execution status"
    public static let permission = SwooshPermission.toolRead
    public static let risk = ToolRisk.readOnly
    public static let approval = ApprovalPolicy.never
    public static let toolset = ToolsetID.launchpads

    public init() {}

    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        SwooshLaunchpadCatalog.platformsResponse()
    }
}

public struct LaunchpadGetPlatformTool: SwooshTool {
    public typealias Input = LaunchpadGetPlatformInput
    public typealias Output = LaunchpadPlatformResponse

    public static let name: ToolName = "launchpad.get_platform"
    public static let displayName = "Launchpad Platform Detail"
    public static let description = "Return launchpad platform docs, required permissions, integration notes, and current limitations"
    public static let permission = SwooshPermission.toolRead
    public static let risk = ToolRisk.readOnly
    public static let approval = ApprovalPolicy.never
    public static let toolset = ToolsetID.launchpads

    public init() {}

    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        guard let response = SwooshLaunchpadCatalog.detail(id: input.id) else {
            throw ToolError.notFound(input.id)
        }
        return response
    }
}

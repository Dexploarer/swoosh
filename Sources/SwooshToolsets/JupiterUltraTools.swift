// SwooshToolsets/JupiterUltraTools.swift
// Jupiter Ultra API — shield (token safety) and routers (liquidity discovery).
// Both are read-only, no approval needed.

import Foundation
import SwooshTools
import JupSwift

// MARK: - Shield (token safety warnings)

public struct JupiterShieldInput: Codable, Sendable {
    /// SPL mint addresses to check for known risks
    public let mints: [String]
    public init(mints: [String]) { self.mints = mints }
}

public struct JupiterTokenWarning: Codable, Sendable {
    public let type: String
    public let message: String
    public let severity: String         // "warning" | "error"
}

public struct JupiterShieldOutput: Codable, Sendable {
    /// Keyed by mint address; empty array means no known warnings
    public let warnings: [String: [JupiterTokenWarning]]
    public var hasAnyWarning: Bool { !warnings.values.allSatisfy { $0.isEmpty } }
}

public struct JupiterShieldTool: SwooshTool {
    public typealias Input = JupiterShieldInput
    public typealias Output = JupiterShieldOutput
    public static let name: ToolName = "jupiter.shield"
    public static let displayName = "Jupiter Shield"
    public static let description = "Check tokens for known risks and scam warnings via Jupiter Shield"
    public static let permission = SwooshPermission.solanaRead
    public static let risk = ToolRisk.readOnly
    public static let approval = ApprovalPolicy.never
    public static let toolset = ToolsetID.solana

    let dependencies: ToolDependencies
    public init(dependencies: ToolDependencies) { self.dependencies = dependencies }

    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        let resp = try await JupiterApi.shield(mints: input.mints)
        let warnings = resp.warnings.mapValues { list in
            list.map { w in JupiterTokenWarning(type: w.type, message: w.message, severity: w.severity) }
        }
        return JupiterShieldOutput(warnings: warnings)
    }
}

// MARK: - Routers (available liquidity sources)

public struct JupiterRoutersInput: Codable, Sendable {
    public init() {}
}

public struct JupiterRouterInfo: Codable, Sendable {
    public let id: String
    public let name: String
    public let iconURL: String
}

public struct JupiterRoutersOutput: Codable, Sendable {
    public let routers: [JupiterRouterInfo]
    public let count: Int
}

public struct JupiterRoutersTool: SwooshTool {
    public typealias Input = JupiterRoutersInput
    public typealias Output = JupiterRoutersOutput
    public static let name: ToolName = "jupiter.routers"
    public static let displayName = "Jupiter Routers"
    public static let description = "List all available Jupiter liquidity routers (DEX sources)"
    public static let permission = SwooshPermission.solanaRead
    public static let risk = ToolRisk.readOnly
    public static let approval = ApprovalPolicy.never
    public static let toolset = ToolsetID.solana

    let dependencies: ToolDependencies
    public init(dependencies: ToolDependencies) { self.dependencies = dependencies }

    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        let resp = try await JupiterApi.routers()
        let routers = resp.map { r in JupiterRouterInfo(id: r.id, name: r.name, iconURL: r.icon) }
        return JupiterRoutersOutput(routers: routers, count: routers.count)
    }
}

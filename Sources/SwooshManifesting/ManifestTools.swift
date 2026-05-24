// SwooshManifesting/ManifestTools.swift — Tool surface for manifestations — 0.1A
//
// Three tools — manifest_now, manifest_history, manifest_get.
//
//   • manifest_now    — user-only kick of the self-improvement loop. Useful
//                       when the agent has just done something unusual and
//                       the user wants to capture it before the day's
//                       scheduled pass.
//   • manifest_history — list recent passes.
//   • manifest_get    — read a specific manifestation report.
//
// The scheduler does the automatic firing; this tool surface is the
// manual "do it now" / "what did you think about" path.

import Foundation
import SwooshTools

public struct ManifestToolDependencies: Sendable {
    public let store: any ManifestationStoring
    public let manifester: Manifester

    public init(store: any ManifestationStoring, manifester: Manifester) {
        self.store = store
        self.manifester = manifester
    }
}

// MARK: - manifest_now

public struct ManifestNowInput: Codable, Sendable {
    public let reason: String?
    public init(reason: String? = "manual") { self.reason = reason }
}

public struct ManifestNowOutput: Codable, Sendable {
    public let id: String
    public let status: ManifestationStatus
    public let proposalCount: Int
    public let summary: String?
}

public struct ManifestNowTool: SwooshTool {
    public typealias Input = ManifestNowInput
    public typealias Output = ManifestNowOutput
    public static let name: ToolName = "manifest_now"
    public static let displayName = "Manifest now"
    public static let description = "Trigger a self-improvement (manifestation) pass immediately."
    public static let permission: SwooshPermission = .manifestRun
    public static let risk: ToolRisk = .medium
    /// Manifesting reads the audit log and emits drafts. We gate it on
    /// human approval so the model can't trigger reflective passes at
    /// arbitrary points in a conversation.
    public static let approval: ApprovalPolicy = .humanOnly
    public static let toolset: ToolsetID = .manifesting

    private let deps: ManifestToolDependencies
    public init(dependencies: ManifestToolDependencies) { self.deps = dependencies }

    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        let result = try await deps.manifester.runOnce(triggerReason: input.reason ?? "manual")
        return Output(
            id: result.id,
            status: result.status,
            proposalCount: result.proposals.count,
            summary: result.summary
        )
    }
}

// MARK: - manifest_history

public struct ManifestHistoryInput: Codable, Sendable {
    public let limit: Int?
    public init(limit: Int? = 10) { self.limit = limit }
}

public struct ManifestHistoryOutput: Codable, Sendable {
    public let manifestations: [Manifestation]
}

public struct ManifestHistoryTool: SwooshTool {
    public typealias Input = ManifestHistoryInput
    public typealias Output = ManifestHistoryOutput
    public static let name: ToolName = "manifest_history"
    public static let displayName = "Recent manifestations"
    public static let description = "List recent self-improvement passes with their status, summary, and proposal counts."
    public static let permission: SwooshPermission = .manifestRead
    public static let risk: ToolRisk = .readOnly
    public static let approval: ApprovalPolicy = .never
    public static let toolset: ToolsetID = .manifesting

    private let deps: ManifestToolDependencies
    public init(dependencies: ManifestToolDependencies) { self.deps = dependencies }

    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        let items = try await deps.store.listRecent(limit: input.limit ?? 10)
        return Output(manifestations: items)
    }
}

// MARK: - manifest_get

public struct ManifestGetInput: Codable, Sendable {
    public let id: String
    public init(id: String) { self.id = id }
}

public struct ManifestGetOutput: Codable, Sendable {
    public let manifestation: Manifestation?
}

public struct ManifestGetTool: SwooshTool {
    public typealias Input = ManifestGetInput
    public typealias Output = ManifestGetOutput
    public static let name: ToolName = "manifest_get"
    public static let displayName = "Read manifestation"
    public static let description = "Fetch a manifestation report — full phase trace and proposal list."
    public static let permission: SwooshPermission = .manifestRead
    public static let risk: ToolRisk = .readOnly
    public static let approval: ApprovalPolicy = .never
    public static let toolset: ToolsetID = .manifesting

    private let deps: ManifestToolDependencies
    public init(dependencies: ManifestToolDependencies) { self.deps = dependencies }

    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        let m = try await deps.store.get(id: input.id)
        return Output(manifestation: m)
    }
}

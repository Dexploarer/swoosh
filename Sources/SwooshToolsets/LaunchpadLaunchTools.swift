// SwooshToolsets/LaunchpadLaunchTools.swift — Token-gated launch actions
//
// These tools require $DTOUR stake to execute. Browsing/analytics
// on launchpad platforms is free (LaunchpadTools.swift); only the
// actual "launch a token" action is gated. 0.4A

import Foundation
import SwooshTools

// MARK: - Shared types

public struct LaunchTokenInput: Codable, Sendable {
    /// Launchpad platform ID (pumpportal, bags, flap, four-meme).
    public let platformID: String
    /// Token name.
    public let name: String
    /// Token ticker / symbol.
    public let symbol: String
    /// Token description / tagline.
    public let description: String
    /// Initial supply (base units). Platforms may override.
    public let initialSupply: UInt64?
    /// Image URL or data URI for the token logo.
    public let imageURL: String?
    /// Platform-specific extra parameters (JSON object).
    public let platformParams: JSONValue?

    public init(
        platformID: String,
        name: String,
        symbol: String,
        description: String,
        initialSupply: UInt64? = nil,
        imageURL: String? = nil,
        platformParams: JSONValue? = nil
    ) {
        self.platformID = platformID
        self.name = name
        self.symbol = symbol
        self.description = description
        self.initialSupply = initialSupply
        self.imageURL = imageURL
        self.platformParams = platformParams
    }
}

public struct LaunchTokenOutput: Codable, Sendable {
    /// Platform that handled the launch.
    public let platform: String
    /// Unsigned transaction bytes (base64) for wallet signing.
    public let unsignedTransaction: String?
    /// Human-readable summary for the user to review before signing.
    public let reviewSummary: String
    /// Whether the launch draft was persisted (for resumable flows).
    public let draftSaved: Bool

    public init(
        platform: String,
        unsignedTransaction: String? = nil,
        reviewSummary: String,
        draftSaved: Bool = false
    ) {
        self.platform = platform
        self.unsignedTransaction = unsignedTransaction
        self.reviewSummary = reviewSummary
        self.draftSaved = draftSaved
    }
}

// MARK: - PumpPortal

public struct PumpPortalLaunchTool: SwooshTool {
    public typealias Input = LaunchTokenInput
    public typealias Output = LaunchTokenOutput

    public static let name: ToolName = "launchpad.pumpportal.launch"
    public static let displayName = "Launch Token (PumpPortal)"
    public static let description = "Create and launch a new token on Pump.fun via PumpPortal. Requires $DTOUR stake."
    public static let permission = SwooshPermission.solanaBuildTransaction
    public static let risk = ToolRisk.critical
    public static let approval = ApprovalPolicy.askEveryTime
    public static let toolset = ToolsetID.launchpads
    public static let isTokenGated = true

    public init() {}

    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        // Delegate to the PumpPortal skill / API client when wired
        throw ToolError.notImplemented("PumpPortal launch execution pending API client registration")
    }
}

// MARK: - Bags

public struct BagsLaunchTool: SwooshTool {
    public typealias Input = LaunchTokenInput
    public typealias Output = LaunchTokenOutput

    public static let name: ToolName = "launchpad.bags.launch"
    public static let displayName = "Launch Token (Bags)"
    public static let description = "Create and launch a new token on Bags.fm. Requires $DTOUR stake."
    public static let permission = SwooshPermission.solanaBuildTransaction
    public static let risk = ToolRisk.critical
    public static let approval = ApprovalPolicy.askEveryTime
    public static let toolset = ToolsetID.launchpads
    public static let isTokenGated = true

    public init() {}

    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        throw ToolError.notImplemented("Bags launch execution pending API client registration")
    }
}

// MARK: - Flap

public struct FlapLaunchTool: SwooshTool {
    public typealias Input = LaunchTokenInput
    public typealias Output = LaunchTokenOutput

    public static let name: ToolName = "launchpad.flap.launch"
    public static let displayName = "Launch Token (Flap)"
    public static let description = "Create and launch a new token on Flap (BNB Chain). Requires $DTOUR stake."
    public static let permission = SwooshPermission.evmBuildTransaction
    public static let risk = ToolRisk.critical
    public static let approval = ApprovalPolicy.askEveryTime
    public static let toolset = ToolsetID.launchpads
    public static let isTokenGated = true

    public init() {}

    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        throw ToolError.notImplemented("Flap launch execution pending contract client registration")
    }
}

// MARK: - Four.meme

public struct FourMemeLaunchTool: SwooshTool {
    public typealias Input = LaunchTokenInput
    public typealias Output = LaunchTokenOutput

    public static let name: ToolName = "launchpad.four_meme.launch"
    public static let displayName = "Launch Token (Four.meme)"
    public static let description = "Create and launch a new token on Four.meme (BNB Chain). Requires $DTOUR stake."
    public static let permission = SwooshPermission.evmBuildTransaction
    public static let risk = ToolRisk.critical
    public static let approval = ApprovalPolicy.askEveryTime
    public static let toolset = ToolsetID.launchpads
    public static let isTokenGated = true

    public init() {}

    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        throw ToolError.notImplemented("Four.meme launch execution pending contract client registration")
    }
}

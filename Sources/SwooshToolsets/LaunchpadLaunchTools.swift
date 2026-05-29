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
    // ── Logo (uploaded to IPFS as a binary file, NOT a URL) ──
    /// Base64-encoded logo image bytes.
    public let imageBase64: String?
    /// MIME type of the logo (e.g. "image/png").
    public let imageMimeType: String?
    // ── Socials (carried in the IPFS metadata) ──
    public let website: String?
    public let twitter: String?
    public let telegram: String?
    // ── Initial dev buy ──
    /// Creator's initial buy, in SOL (0 to skip). Solana platforms.
    public let devBuySOL: Double?
    /// Slippage percent for the dev buy.
    public let slippagePercent: Double?
    /// Priority fee in SOL for the dev buy.
    public let priorityFeeSOL: Double?
    /// Platform-specific extra parameters (JSON object).
    public let platformParams: JSONValue?
    // NOTE: token supply/decimals are NOT inputs — every supported
    // launchpad fixes them by protocol (pump.fun 1e9 / 6dp).

    public init(
        platformID: String,
        name: String,
        symbol: String,
        description: String,
        imageBase64: String? = nil,
        imageMimeType: String? = nil,
        website: String? = nil,
        twitter: String? = nil,
        telegram: String? = nil,
        devBuySOL: Double? = nil,
        slippagePercent: Double? = nil,
        priorityFeeSOL: Double? = nil,
        platformParams: JSONValue? = nil
    ) {
        self.platformID = platformID
        self.name = name
        self.symbol = symbol
        self.description = description
        self.imageBase64 = imageBase64
        self.imageMimeType = imageMimeType
        self.website = website
        self.twitter = twitter
        self.telegram = telegram
        self.devBuySOL = devBuySOL
        self.slippagePercent = slippagePercent
        self.priorityFeeSOL = priorityFeeSOL
        self.platformParams = platformParams
    }
}

public struct LaunchTokenOutput: Codable, Sendable {
    /// Platform that handled the launch.
    public let platform: String
    /// Unsigned transaction bytes (base64) for wallet signing. Nil while a
    /// launch is only *prepared* (broadcast not yet wired).
    public let unsignedTransaction: String?
    /// IPFS metadata URI produced for the token (when the metadata was pinned).
    public let metadataUri: String?
    /// True when the launch was prepared (metadata pinned + request assembled)
    /// but NOT broadcast — no funds moved.
    public let prepared: Bool
    /// Human-readable summary for the user to review before signing.
    public let reviewSummary: String
    /// Whether the launch draft was persisted (for resumable flows).
    public let draftSaved: Bool

    public init(
        platform: String,
        unsignedTransaction: String? = nil,
        metadataUri: String? = nil,
        prepared: Bool = false,
        reviewSummary: String,
        draftSaved: Bool = false
    ) {
        self.platform = platform
        self.unsignedTransaction = unsignedTransaction
        self.metadataUri = metadataUri
        self.prepared = prepared
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

    private let client: PumpPortalLaunchClient

    public init(client: PumpPortalLaunchClient = PumpPortalLaunchClient()) {
        self.client = client
    }

    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        // PREPARE-ONLY: pin metadata to IPFS + assemble the create request for
        // review. Broadcast (which moves funds) is intentionally not wired —
        // see PumpPortalLaunchClient. All firewall/approval/token gates have
        // already passed by the time this runs (ToolRegistry.call).
        guard let base64 = input.imageBase64, let imageData = Data(base64Encoded: base64), !imageData.isEmpty else {
            throw ToolError.invalidInput("A logo image is required to prepare a pump.fun launch.")
        }
        // Bounds — no funds move here, but pin the expected ranges now so the
        // future sign/broadcast path inherits a validated input.
        if let buy = input.devBuySOL, buy < 0 || buy > 100 {
            throw ToolError.invalidInput("Dev buy must be between 0 and 100 SOL.")
        }
        if let slip = input.slippagePercent, slip < 0 || slip > 50 {
            throw ToolError.invalidInput("Slippage must be between 0 and 50%.")
        }
        if let fee = input.priorityFeeSOL, fee < 0 || fee > 1 {
            throw ToolError.invalidInput("Priority fee must be between 0 and 1 SOL.")
        }
        let metadataUri = try await client.uploadMetadata(
            name: input.name,
            symbol: input.symbol,
            description: input.description,
            imageData: imageData,
            mimeType: input.imageMimeType ?? "image/png",
            twitter: input.twitter,
            telegram: input.telegram,
            website: input.website
        )
        let devBuy = input.devBuySOL ?? 0
        let summary = """
        Prepared pump.fun launch — NOT broadcast (no funds moved).
        • Token: \(input.name) ($\(input.symbol))
        • Metadata (IPFS): \(metadataUri)
        • Dev buy: \(devBuy) SOL\(devBuy > 0 ? " · slippage \(input.slippagePercent ?? 5)% · priority \(input.priorityFeeSOL ?? 0.00005) SOL" : "")
        • Fees on launch (when broadcast): 0.5% Local / 1% Lightning on the dev buy, + Solana network + pump.fun protocol fees.
        Supply is fixed by pump.fun (1,000,000,000 / 6 decimals).
        To complete the launch, the create transaction must be signed and broadcast — that step is not yet enabled.
        """
        return Output(
            platform: "pump.fun",
            unsignedTransaction: nil,
            metadataUri: metadataUri,
            prepared: true,
            reviewSummary: summary,
            draftSaved: false
        )
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

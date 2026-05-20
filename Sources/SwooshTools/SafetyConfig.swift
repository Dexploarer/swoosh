// SwooshTools/SafetyConfig.swift — Safety Feature Flags
//
// Every "do not build in 0.4A" item has a config flag that defaults to
// disabled but can be unlocked in future milestones. Nothing is hardcoded
// as permanently impossible — just gated behind explicit configuration.

import Foundation

// MARK: - Safety configuration

/// Controls which advanced capabilities are enabled.
/// All flags default to `false` for 0.4A. Future milestones
/// unlock them behind proper guardrails.
public struct SwooshSafetyConfig: Codable, Sendable, Equatable {

    // ── Trading & financial ───────────────────────────────────────

    /// When true, enables autonomous trading tools (swap, limit order, etc.).
    /// 0.4A default: false. Requires dedicated audit trail + risk limits.
    public var autonomousTradingEnabled: Bool

    /// When true, the model may request trading actions that require human approval.
    /// 0.4A default: false. Human approval stays mandatory.
    public var humanPromptedTradingEnabled: Bool

    /// When true, enables swap execution tools (DEX aggregator calls).
    /// 0.4A default: false. Requires slippage protection + preview.
    public var swapExecutionEnabled: Bool

    /// When true, enables portfolio recommendation tools.
    /// 0.4A default: false. Requires disclaimers + regulatory compliance.
    public var portfolioRecommendationsEnabled: Bool

    // ── Key management ────────────────────────────────────────────

    /// When true, allows Swoosh to manage private keys in Keychain.
    /// 0.4A default: false. Requires HSM-grade isolation + backup flow.
    public var privateKeyCustodyEnabled: Bool

    /// When true, allows seed phrase ingestion for wallet recovery.
    /// 0.4A default: false. Requires secure enclave + zero-knowledge path.
    public var seedPhraseIngestionEnabled: Bool

    // ── Data ingestion ────────────────────────────────────────────

    /// When true, allows browser cookie ingestion for authenticated scraping.
    /// 0.4A default: false. Requires consent + expiry + audit.
    public var cookieIngestionEnabled: Bool

    // ── Execution boundaries ──────────────────────────────────────

    /// When true, allows shell tools to interact with blockchain signing.
    /// 0.4A default: false. Prevents shell → wallet escalation.
    public var shellToBlockchainBridgeEnabled: Bool

    /// When true, allows the model to approve its own tool calls.
    /// 0.4A default: false. Human-in-the-loop is mandatory.
    public var modelSelfApprovalEnabled: Bool

    /// When true, mainnet write tools are enabled by default.
    /// 0.4A default: false. Mainnet writes require explicit opt-in.
    public var mainnetWritesByDefault: Bool

    // ── Defaults ──────────────────────────────────────────────────

    public init(
        autonomousTradingEnabled: Bool = false,
        humanPromptedTradingEnabled: Bool = false,
        swapExecutionEnabled: Bool = false,
        portfolioRecommendationsEnabled: Bool = false,
        privateKeyCustodyEnabled: Bool = false,
        seedPhraseIngestionEnabled: Bool = false,
        cookieIngestionEnabled: Bool = false,
        shellToBlockchainBridgeEnabled: Bool = false,
        modelSelfApprovalEnabled: Bool = false,
        mainnetWritesByDefault: Bool = false
    ) {
        self.autonomousTradingEnabled = autonomousTradingEnabled
        self.humanPromptedTradingEnabled = humanPromptedTradingEnabled
        self.swapExecutionEnabled = swapExecutionEnabled
        self.portfolioRecommendationsEnabled = portfolioRecommendationsEnabled
        self.privateKeyCustodyEnabled = privateKeyCustodyEnabled
        self.seedPhraseIngestionEnabled = seedPhraseIngestionEnabled
        self.cookieIngestionEnabled = cookieIngestionEnabled
        self.shellToBlockchainBridgeEnabled = shellToBlockchainBridgeEnabled
        self.modelSelfApprovalEnabled = modelSelfApprovalEnabled
        self.mainnetWritesByDefault = mainnetWritesByDefault
    }

    private enum CodingKeys: String, CodingKey {
        case autonomousTradingEnabled
        case humanPromptedTradingEnabled
        case swapExecutionEnabled
        case portfolioRecommendationsEnabled
        case privateKeyCustodyEnabled
        case seedPhraseIngestionEnabled
        case cookieIngestionEnabled
        case shellToBlockchainBridgeEnabled
        case modelSelfApprovalEnabled
        case mainnetWritesByDefault
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            autonomousTradingEnabled: try container.decodeIfPresent(Bool.self, forKey: .autonomousTradingEnabled) ?? false,
            humanPromptedTradingEnabled: try container.decodeIfPresent(Bool.self, forKey: .humanPromptedTradingEnabled) ?? false,
            swapExecutionEnabled: try container.decodeIfPresent(Bool.self, forKey: .swapExecutionEnabled) ?? false,
            portfolioRecommendationsEnabled: try container.decodeIfPresent(Bool.self, forKey: .portfolioRecommendationsEnabled) ?? false,
            privateKeyCustodyEnabled: try container.decodeIfPresent(Bool.self, forKey: .privateKeyCustodyEnabled) ?? false,
            seedPhraseIngestionEnabled: try container.decodeIfPresent(Bool.self, forKey: .seedPhraseIngestionEnabled) ?? false,
            cookieIngestionEnabled: try container.decodeIfPresent(Bool.self, forKey: .cookieIngestionEnabled) ?? false,
            shellToBlockchainBridgeEnabled: try container.decodeIfPresent(Bool.self, forKey: .shellToBlockchainBridgeEnabled) ?? false,
            modelSelfApprovalEnabled: try container.decodeIfPresent(Bool.self, forKey: .modelSelfApprovalEnabled) ?? false,
            mainnetWritesByDefault: try container.decodeIfPresent(Bool.self, forKey: .mainnetWritesByDefault) ?? false
        )
    }

    public static let defaultAgent = SwooshSafetyConfig()

    /// Development-only config. Some flags relaxed for testing.
    /// Still does NOT enable private key custody or seed phrase ingestion.
    public static let development = SwooshSafetyConfig(
        humanPromptedTradingEnabled: true,
        swapExecutionEnabled: true,
        portfolioRecommendationsEnabled: true,
        mainnetWritesByDefault: false  // even in dev, mainnet stays locked
    )

    public static let trader = SwooshSafetyConfig(
        humanPromptedTradingEnabled: true,
        swapExecutionEnabled: true,
        portfolioRecommendationsEnabled: true,
        mainnetWritesByDefault: true
    )

    public static let autonomous = SwooshSafetyConfig(
        autonomousTradingEnabled: true,
        humanPromptedTradingEnabled: true,
        swapExecutionEnabled: true,
        portfolioRecommendationsEnabled: true,
        privateKeyCustodyEnabled: true,
        seedPhraseIngestionEnabled: true,
        cookieIngestionEnabled: true,
        shellToBlockchainBridgeEnabled: true,
        modelSelfApprovalEnabled: true,
        mainnetWritesByDefault: true
    )
}

// MARK: - Safety violation

public enum SafetyViolation: Error, Sendable {
    case featureDisabled(String)
    case privateKeyRejected
    case seedPhraseRejected
    case cookieRejected
    case mainnetWriteDenied
    case modelSelfApprovalDenied
    case shellBlockchainBridgeDenied
    case autonomousTradingDenied
    case humanPromptedTradingDenied
    case swapExecutionDenied

    public var localizedDescription: String {
        switch self {
        case .featureDisabled(let feature):
            return "Feature '\(feature)' is disabled in current safety configuration."
        case .privateKeyRejected:
            return "Private key ingestion is disabled. Use WalletConnect or external wallet."
        case .seedPhraseRejected:
            return "Seed phrase ingestion is disabled. Use WalletConnect or external wallet."
        case .cookieRejected:
            return "Cookie ingestion is disabled."
        case .mainnetWriteDenied:
            return "Mainnet write operations require explicit permission."
        case .modelSelfApprovalDenied:
            return "The model cannot approve its own tool calls."
        case .shellBlockchainBridgeDenied:
            return "Shell-to-blockchain bridge is disabled."
        case .autonomousTradingDenied:
            return "Autonomous trading is disabled."
        case .humanPromptedTradingDenied:
            return "Human-prompted trading is disabled."
        case .swapExecutionDenied:
            return "Swap execution is disabled."
        }
    }
}

// MARK: - Safety guard

/// Convenience methods for checking safety config before tool execution.
extension SwooshSafetyConfig {

    public func requireAutonomousTrading() throws {
        guard autonomousTradingEnabled else { throw SafetyViolation.autonomousTradingDenied }
    }

    public func requireHumanPromptedTrading() throws {
        guard humanPromptedTradingEnabled else { throw SafetyViolation.humanPromptedTradingDenied }
    }

    public func requireSwapExecution() throws {
        guard swapExecutionEnabled else { throw SafetyViolation.swapExecutionDenied }
    }

    public func requirePrivateKeyCustody() throws {
        guard privateKeyCustodyEnabled else { throw SafetyViolation.privateKeyRejected }
    }

    public func requireSeedPhraseIngestion() throws {
        guard seedPhraseIngestionEnabled else { throw SafetyViolation.seedPhraseRejected }
    }

    public func requireCookieIngestion() throws {
        guard cookieIngestionEnabled else { throw SafetyViolation.cookieRejected }
    }

    public func requireShellToBlockchainBridge() throws {
        guard shellToBlockchainBridgeEnabled else { throw SafetyViolation.shellBlockchainBridgeDenied }
    }

    public func requireModelSelfApproval() throws {
        guard modelSelfApprovalEnabled else { throw SafetyViolation.modelSelfApprovalDenied }
    }

    public func requireMainnetWritesByDefault() throws {
        guard mainnetWritesByDefault else { throw SafetyViolation.mainnetWriteDenied }
    }
}

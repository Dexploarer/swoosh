// SwooshToolsets/Exports.swift — Default Tool Registration (0.4B)
//
// Registers all 0.4A tools into the ToolRegistry.
// P0: core, memory, permissions, scout, audit, files, git, swiftDev, workflow, evm, solana
// P1: web, browser, apple, xcode, mcp (deferred)
// Self-improvement pillars: skills, goals, manifesting
// Media generation: image, video, 3D, music (opt-in via mediaGen bundle)

import Foundation
import SwooshTools
import SwooshSkills
import SwooshGoals
import SwooshManifesting
import SwooshCron
import SwooshCalendar
import SwooshMCP
import SwooshImageGen
import SwooshMusic

// ═══════════════════════════════════════════════════════════════════
// MARK: - Self-improvement pillar dependencies
// ═══════════════════════════════════════════════════════════════════

/// Optional bundle of dependencies for the self-improvement pillars.
/// Passing `nil` for any field skips registering that pillar's tools.
public struct SelfImprovementDependencies: Sendable {
    public let skills: SkillToolDependencies?
    public let goals: GoalToolDependencies?
    public let manifest: ManifestToolDependencies?
    public let cron: CronToolDependencies?
    public let calendar: CalendarToolDependencies?

    public init(
        skills: SkillToolDependencies? = nil,
        goals: GoalToolDependencies? = nil,
        manifest: ManifestToolDependencies? = nil,
        cron: CronToolDependencies? = nil,
        calendar: CalendarToolDependencies? = nil
    ) {
        self.skills = skills
        self.goals = goals
        self.manifest = manifest
        self.cron = cron
        self.calendar = calendar
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Media generation dependencies
// ═══════════════════════════════════════════════════════════════════

/// Optional bundle of provider instances for media-generation tools.
/// Passing `nil` for any field skips registering that tool. Wire the
/// providers daemon-side using `CapabilityRouter.activeXProvider()` so
/// the picker's selection drives which model the agent reaches.
public struct MediaGenDependencies: Sendable {
    public let imageProvider: (any ImageGenProviding)?
    public let videoProvider: (any VideoGenProviding)?
    public let threeDProvider: (any ThreeDGenProviding)?
    public let musicProvider: (any MusicProviding)?
    public let cacheDir: URL?
    public let audioDownloader: (any AudioDownloading)?

    public init(
        imageProvider: (any ImageGenProviding)? = nil,
        videoProvider: (any VideoGenProviding)? = nil,
        threeDProvider: (any ThreeDGenProviding)? = nil,
        musicProvider: (any MusicProviding)? = nil,
        cacheDir: URL? = nil,
        audioDownloader: (any AudioDownloading)? = nil
    ) {
        self.imageProvider = imageProvider
        self.videoProvider = videoProvider
        self.threeDProvider = threeDProvider
        self.musicProvider = musicProvider
        self.cacheDir = cacheDir
        self.audioDownloader = audioDownloader
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Default tool registrar
// ═══════════════════════════════════════════════════════════════════

public enum DefaultToolRegistrar {
    public static func registerAll(
        into registry: ToolRegistry,
        dependencies: ToolDependencies,
        selfImprovement: SelfImprovementDependencies = SelfImprovementDependencies(),
        mcp: MCPDependencies? = nil,
        mediaGen: MediaGenDependencies? = nil,
        nitrogen: NitroGenController? = nil
    ) async {
        await registerCore(into: registry, dependencies: dependencies)
        await registerMemory(into: registry, dependencies: dependencies)
        await registerPermissions(into: registry, dependencies: dependencies)
        await registerScout(into: registry, dependencies: dependencies)
        await registerAudit(into: registry, dependencies: dependencies)
        await registerTerminal(into: registry, dependencies: dependencies)
        await registerFiles(into: registry, dependencies: dependencies)
        await registerGit(into: registry, dependencies: dependencies)
        await registerSwiftDev(into: registry, dependencies: dependencies)
        await registerWeb(into: registry, dependencies: dependencies)
        await registerWorkflow(into: registry, dependencies: dependencies)
        await registerEVM(into: registry, dependencies: dependencies)
        await registerSolana(into: registry, dependencies: dependencies)
        await registerJupiter(into: registry, dependencies: dependencies)
        await registerLaunchpads(into: registry)
        await registerHyperliquid(into: registry, dependencies: dependencies)
        await registerUniswap(into: registry, dependencies: dependencies)
        if let skills = selfImprovement.skills {
            await registerSkills(into: registry, dependencies: skills)
        }
        if let goals = selfImprovement.goals {
            await registerGoals(into: registry, dependencies: goals)
        }
        if let manifest = selfImprovement.manifest {
            await registerManifesting(into: registry, dependencies: manifest)
        }
        if let cron = selfImprovement.cron {
            await registerCron(into: registry, dependencies: cron)
        }
        if let calendar = selfImprovement.calendar {
            await registerCalendar(into: registry, dependencies: calendar)
        }
        if let mcp = mcp {
            await registerMCP(into: registry, dependencies: dependencies, mcp: mcp)
        }
        if let mediaGen = mediaGen {
            await registerMediaGen(into: registry, mediaGen: mediaGen)
        }
        #if os(macOS)
        if let nitrogen = nitrogen {
            await registerNitroGen(into: registry, controller: nitrogen)
        }
        #endif
    }

    // ── MCP ───────────────────────────────────────────────────────
    // Three agent-facing tools — list_servers, list_tools, call.
    // Trust mutations (addServer/enableServer/disableServer/removeServer/
    // allowTool/denyTool) are intentionally not registered as tools;
    // those flows belong to the CLI, not the agent.
    static func registerMCP(
        into registry: ToolRegistry,
        dependencies: ToolDependencies,
        mcp: MCPDependencies
    ) async {
        await registry.register(TypeErasedTool(MCPListServersTool(mcp: mcp)))
        await registry.register(TypeErasedTool(MCPListToolsTool(mcp: mcp)))
        await registry.register(TypeErasedTool(MCPCallTool(mcp: mcp, audit: dependencies.audit)))
    }

    // ── Self-improvement pillars ──────────────────────────────────
    static func registerSkills(into registry: ToolRegistry, dependencies: SkillToolDependencies) async {
        await registry.register(TypeErasedTool(SkillListTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(SkillGetTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(SkillSearchTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(SkillProposeTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(SkillInstallTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(SkillManageTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(SkillApproveTool(dependencies: dependencies)))
    }

    static func registerGoals(into registry: ToolRegistry, dependencies: GoalToolDependencies) async {
        await registry.register(TypeErasedTool(GoalSetTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(GoalStatusTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(GoalAbandonTool(dependencies: dependencies)))
    }

    static func registerManifesting(into registry: ToolRegistry, dependencies: ManifestToolDependencies) async {
        await registry.register(TypeErasedTool(ManifestNowTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(ManifestHistoryTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(ManifestGetTool(dependencies: dependencies)))
    }

    static func registerCron(into registry: ToolRegistry, dependencies: CronToolDependencies) async {
        await registry.register(TypeErasedTool(CronJobTool(dependencies: dependencies)))
    }

    static func registerCalendar(into registry: ToolRegistry, dependencies: CalendarToolDependencies) async {
        await registry.register(TypeErasedTool(CalendarListTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(CalendarManageTool(dependencies: dependencies)))
    }

    // ── Core ──────────────────────────────────────────────────────
    static func registerWeb(into registry: ToolRegistry, dependencies: ToolDependencies) async {
        await registry.register(TypeErasedTool(WebSearchTool(dependencies: dependencies)))
    }

    static func registerCore(into registry: ToolRegistry, dependencies: ToolDependencies) async {
        await registry.register(TypeErasedTool(CoreStatusTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(ExplainContextTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(ListToolsetsTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(ListToolsTool(dependencies: dependencies, registry: registry)))
        await registry.register(TypeErasedTool(GetToolSchemaTool(dependencies: dependencies, registry: registry)))
    }

    // ── Memory / Vault ────────────────────────────────────────────
    static func registerMemory(into registry: ToolRegistry, dependencies: ToolDependencies) async {
        await registry.register(TypeErasedTool(ListApprovedMemoriesTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(SearchApprovedMemoriesTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(GetApprovedMemoryTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(ListCandidatesTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(GetCandidateTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(ProposeCandidateTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(ApproveCandidateTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(RejectCandidateTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(EditCandidateTool(dependencies: dependencies)))
    }

    // ── Permissions ───────────────────────────────────────────────
    static func registerPermissions(into registry: ToolRegistry, dependencies: ToolDependencies) async {
        await registry.register(TypeErasedTool(PermissionSummaryTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(PermissionGetTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(PermissionRequestTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(ListPendingApprovalsTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(ResolveApprovalTool(dependencies: dependencies)))
    }

    // ── Scout ─────────────────────────────────────────────────────
    static func registerScout(into registry: ToolRegistry, dependencies: ToolDependencies) async {
        await registry.register(TypeErasedTool(ScoutListSourcesTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(ScoutStatusTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(ScoutRunTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(ScoutGetReportTool(dependencies: dependencies)))
    }

    // ── Audit ─────────────────────────────────────────────────────
    static func registerAudit(into registry: ToolRegistry, dependencies: ToolDependencies) async {
        await registry.register(TypeErasedTool(AuditTailTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(AuditSearchTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(AuditGetEventTool(dependencies: dependencies)))
    }

    // ── Terminal ──────────────────────────────────────────────────
    static func registerTerminal(into registry: ToolRegistry, dependencies: ToolDependencies) async {
        await registry.register(TypeErasedTool(TerminalBackendsTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(TerminalConfigureTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(TerminalRunTool(dependencies: dependencies)))
    }

    // ── Files ─────────────────────────────────────────────────────
    static func registerFiles(into registry: ToolRegistry, dependencies: ToolDependencies) async {
        await registry.register(TypeErasedTool(FileListTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(FileReadTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(FileSearchTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(FileWriteTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(FilePatchTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(FileDeleteTool(dependencies: dependencies)))
    }

    // ── Git ────────────────────────────────────────────────────────
    static func registerGit(into registry: ToolRegistry, dependencies: ToolDependencies) async {
        await registry.register(TypeErasedTool(GitStatusTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(GitDiffTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(GitLogTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(GitBranchListTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(GitApplyPatchTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(GitCommitTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(GitCheckoutTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(GitPushTool(dependencies: dependencies)))
    }

    // ── Swift dev ─────────────────────────────────────────────────
    static func registerSwiftDev(into registry: ToolRegistry, dependencies: ToolDependencies) async {
        await registry.register(TypeErasedTool(SwiftPackageDescribeTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(SwiftBuildTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(SwiftTestTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(SwiftFormatCheckTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(SwiftDiagnosticsTool(dependencies: dependencies)))
    }

    // ── Workflow ──────────────────────────────────────────────────
    static func registerWorkflow(into registry: ToolRegistry, dependencies: ToolDependencies) async {
        await registry.register(TypeErasedTool(WorkflowDraftFromSessionTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(WorkflowListDraftsTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(WorkflowGetDraftTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(WorkflowSaveDraftTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(WorkflowEnableTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(WorkflowRunDryTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(WorkflowRunTool(dependencies: dependencies)))
    }

    // ── EVM ───────────────────────────────────────────────────────
    static func registerEVM(into registry: ToolRegistry, dependencies: ToolDependencies) async {
        guard dependencies.evmClient != nil else { return }
        await registry.register(TypeErasedTool(EVMChainInfoTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(EVMAddressValidateTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(EVMAccountBalanceNativeTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(EVMAccountNonceTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(EVMContractGetCodeTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(EVMContractCallTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(EVMContractGetLogsTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(EVMERC20BalanceTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(EVMERC20AllowanceTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(EVMABIEncodeCallTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(EVMABIDecodeResultTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(EVMTxEstimateGasTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(EVMTxPreflightTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(EVMTxBuildNativeTransferTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(EVMTxBuildContractCallTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(EVMERC20BuildTransferTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(EVMERC20BuildApproveTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(EVMWalletConnectTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(EVMWalletAccountsTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(EVMTxRequestSignatureTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(EVMTxBroadcastSignedTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(EVMTxGetReceiptTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(EVMTxGetByHashTool(dependencies: dependencies)))
    }

    // ── Solana ────────────────────────────────────────────────────
    static func registerSolana(into registry: ToolRegistry, dependencies: ToolDependencies) async {
        guard dependencies.solanaClient != nil else { return }
        await registry.register(TypeErasedTool(SolanaClusterInfoTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(SolanaAddressValidateTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(SolanaAccountBalanceTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(SolanaAccountInfoTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(SolanaTokenAccountBalanceTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(SolanaTokenAccountsByOwnerTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(SolanaSignaturesForAddressTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(SolanaGetTransactionTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(SolanaGetSignatureStatusesTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(SolanaGetLatestBlockhashTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(SolanaTxSimulateTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(SolanaBuildSOLTransferTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(SolanaBuildSPLTransferTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(SolanaWalletConnectTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(SolanaWalletAccountsTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(SolanaTxRequestSignatureTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(SolanaTxSendSignedTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(SolanaRequestAirdropTool(dependencies: dependencies)))
    }

    // ── Jupiter (Solana DEX aggregator) ───────────────────────────
    // Jupiter tools talk to the Jupiter HTTP API directly.
    // they do not depend on the injected Solana RPC client, so the hook
    // is unconditional. Write paths stay permissioned + trading-gated.
    static func registerJupiter(into registry: ToolRegistry, dependencies: ToolDependencies) async {
        // Swap
        await registry.register(TypeErasedTool(JupiterQuoteTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(JupiterSwapTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(JupiterBuildOrderTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(JupiterExecuteTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(JupiterBalancesTool(dependencies: dependencies)))
        // Tokens
        await registry.register(TypeErasedTool(JupiterPriceTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(JupiterTokenInfoTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(JupiterTradableTokensTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(JupiterTaggedTokensTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(JupiterNewTokensTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(JupiterMarketMintsTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(JupiterAllTokensTool(dependencies: dependencies)))
        // Ultra (shield / routers)
        await registry.register(TypeErasedTool(JupiterShieldTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(JupiterRoutersTool(dependencies: dependencies)))
        // Recurring (DCA)
        await registry.register(TypeErasedTool(JupiterCreateDCATool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(JupiterListDCATool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(JupiterCancelDCATool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(JupiterPriceDepositTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(JupiterPriceWithdrawTool(dependencies: dependencies)))
        // Trigger (limit orders)
        await registry.register(TypeErasedTool(JupiterCreateLimitOrderTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(JupiterGetLimitOrdersTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(JupiterCancelLimitOrderTool(dependencies: dependencies)))
    }

    // ── Launchpads ────────────────────────────────────────────────
    // Catalog tools are free. Launch tools are token-gated ($DTOUR stake).
    static func registerLaunchpads(into registry: ToolRegistry) async {
        // Free: browse + analytics
        await registry.register(TypeErasedTool(LaunchpadListPlatformsTool()))
        await registry.register(TypeErasedTool(LaunchpadGetPlatformTool()))
        // Token-gated: launch actions (isTokenGated = true)
        await registry.register(TypeErasedTool(PumpPortalLaunchTool()))
        await registry.register(TypeErasedTool(BagsLaunchTool()))
        await registry.register(TypeErasedTool(FlapLaunchTool()))
        await registry.register(TypeErasedTool(FourMemeLaunchTool()))
    }

    // ── Hyperliquid (perps DEX) ───────────────────────────────────
    // Market-data tools use a keyless HyperliquidClient; trade tools
    // load a private key from the Keychain via `dependencies.secrets`
    // at call time. Both groups use their own HTTP client, so the hook
    // is unconditional. Trade tools stay `hyperliquidTrade`-permissioned
    // and `askEveryTime`.
    static func registerHyperliquid(into registry: ToolRegistry, dependencies: ToolDependencies) async {
        // Market data (read-only)
        await registry.register(TypeErasedTool(HLAllMidsTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(HLL2BookTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(HLUserStateTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(HLOpenOrdersTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(HLUserFillsTool(dependencies: dependencies)))
        // Trading (permissioned, askEveryTime)
        await registry.register(TypeErasedTool(HLLimitOrderTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(HLMarketOrderTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(HLCancelOrderTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(HLCancelAllTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(HLUpdateLeverageTool(dependencies: dependencies)))
    }

    // ── Uniswap (EVM DEX) ─────────────────────────────────────────
    // Uniswap quote uses the injected EVM RPC client (QuoterV2 eth_call),
    // so this hook is gated on `evmClient` being present — same posture
    // as registerEVM. The build-swap tool returns an unsigned tx only.
    static func registerUniswap(into registry: ToolRegistry, dependencies: ToolDependencies) async {
        guard dependencies.evmClient != nil else { return }
        await registry.register(TypeErasedTool(UniswapQuoteTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(UniswapSwapTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(UniswapPoolTool(dependencies: dependencies)))
    }

    // ── NitroGen (gaming agent) ───────────────────────────────────
    #if os(macOS)
    static func registerNitroGen(into registry: ToolRegistry, controller: NitroGenController) async {
        await registry.register(TypeErasedTool(NitroGenStartTool(controller: controller)))
        await registry.register(TypeErasedTool(NitroGenStopTool(controller: controller)))
        await registry.register(TypeErasedTool(NitroGenStatusTool(controller: controller)))
        await registry.register(TypeErasedTool(NitroGenScreenshotTool(controller: controller)))

        // Gaming navigation tools (voice-driven game search/click/type)
        await registry.register(TypeErasedTool(GamingSearchGameTool()))
        await registry.register(TypeErasedTool(GamingClickElementTool()))
        await registry.register(TypeErasedTool(GamingTypeTextTool()))
        await registry.register(TypeErasedTool(GamingNavigateURLTool()))
        await registry.register(TypeErasedTool(GamingScreenshotWebTool()))
        await registry.register(TypeErasedTool(GamingSelectPlatformTool()))
    }
    #endif
}

// SwooshToolsets/ToolRegistrar.swift — Default Tool Registration
//
// Registers all 0.4A tools into the ToolRegistry.
// P0: core, memory, permissions, scout, audit, files, git, swiftDev, workflow, evm, solana
// P1: web, browser, apple, xcode, mcp (deferred)

import Foundation
import SwooshTools

// ═══════════════════════════════════════════════════════════════════
// MARK: - Default tool registrar
// ═══════════════════════════════════════════════════════════════════

public enum DefaultToolRegistrar {
    public static func registerAll(
        into registry: ToolRegistry,
        dependencies: ToolDependencies
    ) async {
        await registerCore(into: registry, dependencies: dependencies)
        await registerMemory(into: registry, dependencies: dependencies)
        await registerPermissions(into: registry, dependencies: dependencies)
        await registerScout(into: registry, dependencies: dependencies)
        await registerAudit(into: registry, dependencies: dependencies)
        await registerFiles(into: registry, dependencies: dependencies)
        await registerGit(into: registry, dependencies: dependencies)
        await registerSwiftDev(into: registry, dependencies: dependencies)
        await registerWorkflow(into: registry, dependencies: dependencies)
        await registerEVM(into: registry, dependencies: dependencies)
        await registerSolana(into: registry, dependencies: dependencies)
    }

    // ── Core ──────────────────────────────────────────────────────
    static func registerCore(into registry: ToolRegistry, dependencies: ToolDependencies) async {
        await registry.register(TypeErasedTool(CoreStatusTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(ExplainContextTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(ListToolsetsTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(ListToolsTool(dependencies: dependencies)))
        await registry.register(TypeErasedTool(GetToolSchemaTool(dependencies: dependencies)))
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
}

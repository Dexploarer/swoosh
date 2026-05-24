// SwooshDaemon/DaemonToolRuntime.swift — 0.9S Tool registry + dependency wiring
//
// Builds the daemon's `ToolRegistry` + matching `ToolDependencies` —
// firewall, audit log, approval centre, file access, process runner,
// RPC clients, wallet bridge, secret resolver. Mounted once at boot
// from `Daemon.swift` and threaded into every API bridge that calls
// tools.

import Foundation
import ActantAgent
import SwooshActantBackend
import SwooshApprovals
import SwooshCore
import SwooshFiles
import SwooshFirewall
import SwooshFlow
import SwooshProcess
import SwooshSecrets
import SwooshTools
import SwooshToolsets
import SwooshWallet

struct DaemonToolRuntime: Sendable {
    let registry: ToolRegistry
    let dependencies: ToolDependencies
    let firewall: SwooshFirewallActor
    let audit: any AuditLogging
    let baselineGrants: Set<SwooshPermission>
    let walletStore: WalletStore
}

func makeDaemonToolRuntime(
    swooshDir: URL,
    backend: AgentBackend,
    grantedPermissions: Set<SwooshPermission>,
    safetyConfig: SwooshSafetyConfig
) async throws -> DaemonToolRuntime {
    // Durable tool audit + approvals — both ride the ActantDB ledger so the
    // audit trail and the pending-approval queue survive daemon restarts.
    let audit: any AuditLogging = ActantAuditLog(backend: backend)
    let firewall = SwooshFirewallActor(granted: grantedPermissions)
    let approvalCenter = SwooshApprovals.ApprovalCenter(
        store: ActantApprovalStore(backend: backend), audit: audit)
    let rootStore = InMemoryRootStore()
    let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        .standardizedFileURL
    await rootStore.add(ApprovedRoot(
        id: "cwd",
        displayName: cwd.lastPathComponent.isEmpty ? cwd.path : cwd.lastPathComponent,
        absolutePath: cwd.path,
        allowedRead: true,
        allowedWrite: true
    ))
    await rootStore.add(ApprovedRoot(
        id: "swoosh-state",
        displayName: ".swoosh",
        absolutePath: swooshDir.standardizedFileURL.path,
        allowedRead: true,
        allowedWrite: true
    ))

    let registry = ToolRegistry(
        firewall: firewall,
        audit: audit,
        approvals: approvalCenter,
        safetyConfig: safetyConfig
    )
    // Secret resolver — backs RPC-endpoint refs and the Hyperliquid
    // trade tools' Keychain-stored private keys. Tools never receive
    // the raw secret value through their input types.
    let secretResolver = KeychainSecretResolver(store: KeychainSecretStore())
    // Concrete JSON-RPC clients. The endpoint URL is resolved per call
    // from the chain/cluster (Keychain ref → env override → public
    // fallback); these clients are read/broadcast only — no private keys.
    let evmClient = URLSessionEVMRPCClient(secrets: secretResolver)
    let solanaClient = URLSessionSolanaRPCClient(secrets: secretResolver)
    let walletStore = WalletStore()
    let walletBridge = LocalWalletBridge(store: walletStore)
    let dependencies = ToolDependencies(
        firewall: firewall,
        audit: audit,
        approvals: approvalCenter,
        safetyConfig: safetyConfig,
        fileAccess: SafeFileAccessor(rootStore: rootStore),
        processRunner: StreamingProcessRunner(approvedRoots: [cwd.path, swooshDir.path]),
        evmClient: evmClient,
        solanaClient: solanaClient,
        walletBridge: walletBridge,
        memoryStore: MemoryStore(backend: backend),
        scoutStore: FileScoutToolStore(url: swooshDir.appendingPathComponent("scout/tool-state.json")),
        workflowStore: FileWorkflowToolStore(url: swooshDir.appendingPathComponent("workflows/tool-drafts.json")),
        workflowStepExecutor: TracingWorkflowStepExecutor(
            inner: RegistryWorkflowStepExecutor(registry: registry),
            recorder: InMemoryWorkflowTraceRecorder(),
            workflowID: "daemon"
        ),
        secrets: secretResolver
    )
    return DaemonToolRuntime(
        registry: registry,
        dependencies: dependencies,
        firewall: firewall,
        audit: audit,
        baselineGrants: grantedPermissions,
        walletStore: walletStore
    )
}

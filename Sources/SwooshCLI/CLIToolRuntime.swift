// SwooshCLI/CLIToolRuntime.swift — Tool-loop runtime for chat and ask
import Foundation
import ActantAgent
import SwooshActantBackend
import SwooshApprovals
import SwooshConfig
import SwooshCron
import SwooshFiles
import SwooshFirewall
import SwooshFlow
import SwooshProcess
import SwooshSecrets
import SwooshSkills
import SwooshTools
import SwooshToolsets

func makeCLIToolRegistry() async throws -> ToolRegistry {
    let audit = SwooshAuditLog()
    let runtimeConfig = loadCLIRuntimeConfig()
    let preset = PermissionProfilePreset(rawValue: runtimeConfig?.permissionProfile ?? "") ?? .developer
    let firewall = SwooshFirewallActor(granted: preset.grantedSwooshPermissions)
    let approvalCenter = SwooshApprovals.ApprovalCenter(store: InMemoryApprovalStore(), audit: audit)
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

    let memoryStore: any MemoryToolStoring
    if let backend = loadCLIBackend() {
        memoryStore = MemoryStore(backend: backend)
    } else {
        memoryStore = InMemoryMemoryToolStore()
    }

    let registry = ToolRegistry(
        firewall: firewall,
        audit: audit,
        approvals: approvalCenter,
        safetyConfig: runtimeConfig?.safetyConfig ?? preset.defaultSafetyConfig
    )
    let stateRoot = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".swoosh", isDirectory: true)
    // Secret resolver + concrete JSON-RPC clients — matches the daemon
    // wiring so `swoosh chat` / `swoosh ask` reach the same crypto
    // toolset the daemon does. Clients are read/broadcast only.
    let secretResolver = KeychainSecretResolver(store: KeychainSecretStore())
    let evmClient = URLSessionEVMRPCClient(secrets: secretResolver)
    let solanaClient = URLSessionSolanaRPCClient(secrets: secretResolver)
    let deps = ToolDependencies(
        firewall: firewall,
        audit: audit,
        approvals: approvalCenter,
        fileAccess: SafeFileAccessor(rootStore: rootStore),
        processRunner: StreamingProcessRunner(approvedRoots: [cwd.path]),
        evmClient: evmClient,
        solanaClient: solanaClient,
        memoryStore: memoryStore,
        scoutStore: FileScoutToolStore(url: stateRoot.appendingPathComponent("scout/tool-state.json")),
        workflowStore: FileWorkflowToolStore(url: stateRoot.appendingPathComponent("workflows/tool-drafts.json")),
        // Wrap the registry executor in SwooshFlow's tracing wrapper
        // so engineering rule #4 ("every workflow is replayable") holds
        // for runtime `workflow.run` calls — the recorder is queryable
        // via `WorkflowTraceRecording.tail`.
        workflowStepExecutor: TracingWorkflowStepExecutor(
            inner: RegistryWorkflowStepExecutor(registry: registry),
            recorder: InMemoryWorkflowTraceRecorder(),
            workflowID: "cli"
        ),
        secrets: secretResolver
    )

    let skillStore = FileSkillStore()
    _ = try? await BundledSkillLoader(
        store: skillStore,
        directory: BundledSkillLoader.defaultDirectory()
    ).loadAll()
    let cronStore = FileCronJobStore()
    await DefaultToolRegistrar.registerAll(
        into: registry,
        dependencies: deps,
        selfImprovement: SelfImprovementDependencies(
            skills: SkillToolDependencies(store: skillStore),
            cron: CronToolDependencies(store: cronStore)
        )
    )
    return registry
}

func loadCLIRuntimeConfig() -> SwooshRuntimeConfig? {
    try? SwooshConfigStore().load(SwooshRuntimeConfig.self)
}

func loadCLIToolPolicy() -> ToolCallPolicy {
    let runtimeConfig = loadCLIRuntimeConfig()
    let preset = PermissionProfilePreset(rawValue: runtimeConfig?.permissionProfile ?? "") ?? .developer
    return runtimeConfig?.toolPolicy ?? preset.defaultToolPolicy
}

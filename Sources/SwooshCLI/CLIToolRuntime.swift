// SwooshCLI/CLIToolRuntime.swift — Tool-loop runtime for chat and ask
import Foundation
import ActantAgent
import SwooshActantBackend
import SwooshApprovals
import SwooshCron
import SwooshFiles
import SwooshFirewall
import SwooshProcess
import SwooshSkills
import SwooshTools
import SwooshToolsets

func makeCLIToolRegistry() async throws -> ToolRegistry {
    let audit = SwooshAuditLog()
    let firewall = SwooshFirewallActor(granted: defaultAgentToolPermissions())
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

    let registry = ToolRegistry(firewall: firewall, audit: audit, approvals: approvalCenter)
    let stateRoot = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".swoosh", isDirectory: true)
    let deps = ToolDependencies(
        firewall: firewall,
        audit: audit,
        approvals: approvalCenter,
        fileAccess: SafeFileAccessor(rootStore: rootStore),
        processRunner: StreamingProcessRunner(approvedRoots: [cwd.path]),
        memoryStore: memoryStore,
        scoutStore: FileScoutToolStore(url: stateRoot.appendingPathComponent("scout/tool-state.json")),
        workflowStore: FileWorkflowToolStore(url: stateRoot.appendingPathComponent("workflows/tool-drafts.json")),
        workflowStepExecutor: RegistryWorkflowStepExecutor(registry: registry)
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

private func defaultAgentToolPermissions() -> Set<SwooshPermission> {
    Set(SwooshPermission.allCases).subtracting([
        .evmMainnetWrite,
        .solanaMainnetWrite,
    ])
}

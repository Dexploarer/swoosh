// SwooshToolsets/ScoutTools.swift — Scout toolset implementations
import Foundation
import SwooshScout
import SwooshTools

public struct ScoutListSourcesTool: SwooshTool {
    public typealias Input = ScoutListSourcesInput; public typealias Output = ScoutListSourcesOutput
    public static let name: ToolName = "scout.list_sources"; public static let displayName = "List Scout Sources"
    public static let description = "List Scout sources"; public static let permission = SwooshPermission.toolRead
    public static let risk = ToolRisk.readOnly; public static let approval = ApprovalPolicy.never; public static let toolset = ToolsetID.scout
    let dependencies: ToolDependencies; public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        let sources = defaultScoutSources(folderURLs: [])
        let infos = sources.map { source in
            ScoutSourceInfo(
                sourceID: source.id,
                displayName: source.displayName,
                kind: source.sensitivity.rawValue,
                enabled: true
            )
        }
        try await dependencies.scoutStore.setSources(infos)
        return ScoutListSourcesOutput(sources: infos)
    }
}

public struct ScoutStatusTool: SwooshTool {
    public typealias Input = ScoutStatusInput; public typealias Output = ScoutStatusOutput
    public static let name: ToolName = "scout.status"; public static let displayName = "Scout Status"
    public static let description = "Show latest scan status"; public static let permission = SwooshPermission.toolRead
    public static let risk = ToolRisk.readOnly; public static let approval = ApprovalPolicy.never; public static let toolset = ToolsetID.scout
    let dependencies: ToolDependencies; public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        try await dependencies.scoutStore.status()
    }
}

public struct ScoutRunTool: SwooshTool {
    public typealias Input = ScoutRunInput; public typealias Output = ScoutRunOutput
    public static let name: ToolName = "scout.run"; public static let displayName = "Run Scout Scan"
    public static let description = "Run approved Scout scan"; public static let permission = SwooshPermission.toolWrite
    public static let risk = ToolRisk.medium; public static let approval = ApprovalPolicy.askEveryTime; public static let toolset = ToolsetID.scout
    let dependencies: ToolDependencies; public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        var folderURLs: [URL] = []
        for bookmarkID in input.selectedFolderBookmarks {
            folderURLs.append(try await dependencies.fileAccess.resolveBookmark(id: bookmarkID))
        }
        let selectedSources = defaultScoutSources(folderURLs: folderURLs)
            .filter { source in input.sourceIDs.isEmpty || input.sourceIDs.contains(source.id) }
        let knownIDs = Set(defaultScoutSources(folderURLs: []).map(\.id))
        let skipped = input.sourceIDs
            .filter { !knownIDs.contains($0) }
            .map { SkippedScoutSource(sourceID: $0, reason: "unknown source") }

        let result = try await ScoutPipeline(sources: selectedSources).run(
            depth: .deep,
            options: ScoutPipelineOptions(permissionMode: .skipUnavailable, minimumConfidence: 0.74)
        )

        if !input.dryRun {
            for candidate in result.candidates {
                _ = try await dependencies.memoryStore.propose(
                    ProposeMemoryCandidateInput(
                        text: candidate.text,
                        category: MemoryCategory(rawValue: candidate.category) ?? .fact,
                        sensitivity: toolSensitivity(fromScoutRawValue: candidate.sensitivity.rawValue),
                        confidence: candidate.confidence,
                        evidence: candidate.evidence.map {
                            SwooshTools.EvidencePointer(sourceID: $0.source, description: $0.detail)
                        }
                    )
                )
            }
        }

        let run = ScoutToolRunRecord(
            reportMarkdown: result.setupReport,
            recordsCreated: result.recordsCollected,
            candidatesCreated: input.dryRun ? 0 : result.candidatesGenerated
        )
        try await dependencies.scoutStore.saveRun(run)

        return ScoutRunOutput(
            scanID: run.id,
            recordsCreated: result.recordsCollected,
            candidatesCreated: input.dryRun ? 0 : result.candidatesGenerated,
            skippedSources: skipped
        )
    }
}

public struct ScoutGetReportTool: SwooshTool {
    public typealias Input = ScoutGetReportInput; public typealias Output = ScoutGetReportOutput
    public static let name: ToolName = "scout.get_report"; public static let displayName = "Get Scout Report"
    public static let description = "Return latest Scout report"; public static let permission = SwooshPermission.toolRead
    public static let risk = ToolRisk.readOnly; public static let approval = ApprovalPolicy.never; public static let toolset = ToolsetID.scout
    let dependencies: ToolDependencies; public init(dependencies: ToolDependencies) { self.dependencies = dependencies }
    public func call(_ input: Input, context: ToolContext) async throws -> Output {
        try await dependencies.scoutStore.report(scanID: input.scanID)
    }
}

private func defaultScoutSources(folderURLs: [URL]) -> [any ScoutSource] {
    var sources: [any ScoutSource] = [
        DeviceSource(),
        InstalledAppsSource(),
        RunningAppsSource(),
        ShellEnvironmentSource(),
        AppUsageSource(),
        FocusModeSource(),
        CalendarSource(),
        RemindersSource(),
        RecentDocumentsSource(),
        HealthSleepSource(),
        MusicHistorySource(),
        ScreenTimeSource(),
    ]
    if !folderURLs.isEmpty {
        sources.append(ProjectFoldersSource(paths: folderURLs))
        sources.append(GitReposSource(paths: folderURLs))
    }
    return sources
}

private func toolSensitivity(fromScoutRawValue rawValue: String) -> SwooshTools.Sensitivity {
    switch rawValue {
    case "low":
        return .normal
    case "medium", "high":
        return .sensitive
    case "critical":
        return .secret
    default:
        return .sensitive
    }
}

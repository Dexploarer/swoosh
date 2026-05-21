// SwooshScout/Pipeline.swift — End-to-end Scout → Redact → Store → Candidates → Review pipeline
//
// This is the main orchestration: runs sources, redacts, stores records,
// generates candidates, stores candidates, produces setup report.

import Foundation

// MARK: - Pipeline runner

public struct ScoutPipelineResult: Sendable {
    public let sourcesScanned: Int
    public let recordsCollected: Int
    public let recordsRedacted: Int
    public let candidatesGenerated: Int
    public let setupReport: String
    public let records: [ScoutRecord]
    public let candidates: [MemoryCandidate]
}

public enum ScoutPermissionMode: Sendable {
    case requestIfNeeded
    case skipUnavailable
}

public struct ExistingMemorySummary: Sendable {
    public let text: String
    public let category: String

    public init(text: String, category: String) {
        self.text = text
        self.category = category
    }
}

public struct ScoutPipelineOptions: Sendable {
    public let permissionMode: ScoutPermissionMode
    public let existingMemories: [ExistingMemorySummary]
    public let minimumConfidence: Double

    public init(
        permissionMode: ScoutPermissionMode = .requestIfNeeded,
        existingMemories: [ExistingMemorySummary] = [],
        minimumConfidence: Double = 0.0
    ) {
        self.permissionMode = permissionMode
        self.existingMemories = existingMemories
        self.minimumConfidence = minimumConfidence
    }
}

public struct ScoutPipeline: Sendable {
    private let sources: [any ScoutSource]
    private let redactor: SecretRedactor

    public init(sources: [any ScoutSource]) {
        self.sources = sources
        self.redactor = SecretRedactor()
    }

    /// Run the full pipeline: scan → redact → generate candidates → produce report
    /// `progress` is called before each source scan with `(current, total, sourceName)`.
    public func run(
        depth: PersonalizationDepth,
        options: ScoutPipelineOptions = ScoutPipelineOptions(),
        log: @Sendable (String) -> Void = { _ in },
        progress: @Sendable (_ current: Int, _ total: Int, _ sourceName: String) -> Void = { _, _, _ in }
    ) async throws -> ScoutPipelineResult {
        let scanProgress = ScanProgress()
        var allRecords: [ScoutRecord] = []
        var sourcesScanned = 0
        var totalRedacted = 0
        let applicableSources = sources.filter { shouldInclude($0, depth: depth) }
        let totalApplicable = applicableSources.count

        // Phase 1: Scan each source
        for (index, source) in applicableSources.enumerated() {
            progress(index + 1, totalApplicable, source.displayName)

            let permStatus = try await source.checkPermission()
            var hasPermission = (permStatus == .granted)

            if !hasPermission {
                switch options.permissionMode {
                case .requestIfNeeded:
                    log("  ⟳ Requesting permission for \(source.displayName)...")
                    let requested = try await source.requestPermission()
                    hasPermission = (requested == .granted)
                case .skipUnavailable:
                    log("  ○ \(source.displayName) — skipped (permission unavailable)")
                }
            }

            guard hasPermission else {
                if options.permissionMode == .requestIfNeeded {
                    log("  ✗ \(source.displayName) — permission denied")
                }
                continue
            }

            log("  ⟳ Scanning \(source.displayName)...")
            let records = try await source.scan(progress: scanProgress)
            sourcesScanned += 1
            log("  ✓ \(source.displayName) — \(records.count) records")

            allRecords.append(contentsOf: records)
        }

        // Phase 2: Redact
        let redactedRecords = allRecords.map { record -> ScoutRecord in
            let redacted = redactor.redact(record)
            if redacted.content != record.content { totalRedacted += 1 }
            return redacted
        }

        if totalRedacted > 0 {
            log("  ⚠ Redacted \(totalRedacted) records containing potential secrets")
        }

        // Phase 3: Generate memory candidates
        let candidates = CandidateReviewPlanner().plan(
            candidates: generateCandidates(from: redactedRecords),
            existingMemories: options.existingMemories,
            minimumConfidence: options.minimumConfidence
        )
        log("  ✓ Generated \(candidates.count) memory candidates")

        // Phase 4: Produce setup report
        let report = generateReport(records: redactedRecords, candidates: candidates)

        return ScoutPipelineResult(
            sourcesScanned: sourcesScanned,
            recordsCollected: allRecords.count,
            recordsRedacted: totalRedacted,
            candidatesGenerated: candidates.count,
            setupReport: report,
            records: redactedRecords,
            candidates: candidates
        )
    }

    // MARK: - Internals

    private func shouldInclude(_ source: any ScoutSource, depth: PersonalizationDepth) -> Bool {
        switch depth {
        case .minimal:    return source.sensitivity <= .low
        case .recommended: return source.sensitivity <= .medium
        case .deep:       return source.sensitivity <= .high
        case .custom:     return true
        }
    }

    private func generateCandidates(from records: [ScoutRecord]) -> [MemoryCandidate] {
        [
            installedAppCandidates(from: recordsMatching(.installedApp, in: records)),
            projectCandidates(from: recordsMatching(.projectInfo, in: records)),
            gitRepoCandidates(from: recordsMatching(.gitRepo, in: records)),
            shellEnvironmentCandidates(from: recordsMatching(.shellEnvironment, in: records)),
            deviceCandidates(from: recordsMatching(.deviceInfo, in: records)),
            appUsageCandidates(from: recordsMatching(.appUsage, in: records)),
            focusModeCandidates(from: recordsMatching(.focusMode, in: records)),
            calendarCandidates(from: recordsMatching(.calendarPattern, in: records)),
            reminderCandidates(from: recordsMatching(.reminderSummary, in: records)),
            sleepCandidates(from: recordsMatching(.healthSleep, in: records)),
            recentDocumentCandidates(from: recordsMatching(.recentDocument, in: records)),
            personalizationSignalCandidates(from: recordsMatching(.personalizationSignal, in: records)),
        ].flatMap { $0 }
    }

    private func recordsMatching(_ kind: RecordKind, in records: [ScoutRecord]) -> [ScoutRecord] {
        records.filter { $0.kind == kind }
    }

    private func installedAppCandidates(from apps: [ScoutRecord]) -> [MemoryCandidate] {
        let appNames = apps.map(\.content)
        return [
            appGroupCandidate(
                from: appNames,
                matching: Self.developmentApps,
                textPrefix: "User is a developer. Development tools:",
                confidence: 0.9
            ),
            appGroupCandidate(
                from: appNames,
                matching: Self.creativeApps,
                textPrefix: "User works with creative/design tools:",
                confidence: 0.85
            ),
            appGroupCandidate(
                from: appNames,
                matching: Self.productivityApps,
                textPrefix: "User uses productivity tools:",
                confidence: 0.85
            ),
        ].compactMap { $0 }
    }

    private func appGroupCandidate(
        from appNames: [String],
        matching knownApps: Set<String>,
        textPrefix: String,
        confidence: Double
    ) -> MemoryCandidate? {
        let matches = appNames.filter { knownApps.contains($0) }
        guard !matches.isEmpty else { return nil }
        return MemoryCandidate(
            text: "\(textPrefix) \(matches.joined(separator: ", ")).",
            category: "profile",
            confidence: confidence,
            sensitivity: .low,
            evidence: matches.map { EvidencePointer(source: "installed_apps", detail: $0) }
        )
    }

    private func projectCandidates(from projects: [ScoutRecord]) -> [MemoryCandidate] {
        [
            projectCandidate(
                from: projects,
                type: "Swift Package",
                label: "Swift package",
                confidence: 0.9,
                evidenceDetail: { $0.metadata["path"] ?? $0.content }
            ),
            projectCandidate(
                from: projects,
                type: "Node.js",
                label: "Node.js project",
                confidence: 0.85,
                evidenceDetail: { $0.content }
            ),
        ].compactMap { $0 }
    }

    private func projectCandidate(
        from projects: [ScoutRecord],
        type: String,
        label: String,
        confidence: Double,
        evidenceDetail: (ScoutRecord) -> String
    ) -> MemoryCandidate? {
        let matches = projects.filter { $0.metadata["type"] == type }
        guard !matches.isEmpty else { return nil }
        return MemoryCandidate(
            text: "User has \(matches.count) \(label)(s): \(matches.map(\.content).joined(separator: ", ")).",
            category: "project",
            confidence: confidence,
            sensitivity: .low,
            evidence: matches.map { EvidencePointer(source: "project_folders", detail: evidenceDetail($0)) }
        )
    }

    private func gitRepoCandidates(from repos: [ScoutRecord]) -> [MemoryCandidate] {
        let githubRepos = repos.filter { ($0.metadata["remote"] ?? "").contains("github.com") }
        guard !githubRepos.isEmpty else { return [] }
        return [
            MemoryCandidate(
                text: "User has \(githubRepos.count) GitHub repo(s) locally.",
                category: "profile",
                confidence: 0.9,
                sensitivity: .low,
                evidence: githubRepos.map { EvidencePointer(source: "git_repos", detail: $0.content) }
            ),
        ]
    }

    private func shellEnvironmentCandidates(from records: [ScoutRecord]) -> [MemoryCandidate] {
        records
            .filter { $0.content.contains("Tools in PATH") }
            .map { record in
                MemoryCandidate(
                    text: "Developer environment: \(record.content)",
                    category: "preference",
                    confidence: 0.8,
                    sensitivity: .low,
                    evidence: [EvidencePointer(source: "shell_env", detail: record.content)]
                )
            }
    }

    private func deviceCandidates(from records: [ScoutRecord]) -> [MemoryCandidate] {
        guard !records.isEmpty else { return [] }
        return [
            MemoryCandidate(
                text: "Device: \(records.map(\.content).joined(separator: ". "))",
                category: "device",
                confidence: 1.0,
                sensitivity: .low,
                evidence: [EvidencePointer(source: "device", detail: "system info")]
            ),
        ]
    }

    private func appUsageCandidates(from records: [ScoutRecord]) -> [MemoryCandidate] {
        guard !records.isEmpty else { return [] }
        let topApps = records.prefix(3).map(\.content).joined(separator: "; ")
        let totalSeconds = records.reduce(0) { sum, record in
            sum + (Int(record.metadata["seconds"] ?? "0") ?? 0)
        }
        let totalHours = Double(totalSeconds) / 3600.0
        return [
            MemoryCandidate(
                text: "Active app usage over the recent window — \(topApps). " +
                    "Total focused time: \(String(format: "%.1f", totalHours))h.",
                category: "workflow",
                confidence: 0.85,
                sensitivity: .high,
                evidence: records.prefix(5).map {
                    EvidencePointer(source: "app_usage", detail: $0.content)
                }
            ),
        ]
    }

    private func focusModeCandidates(from records: [ScoutRecord]) -> [MemoryCandidate] {
        primaryRecordCandidate(from: records, category: "preference", confidence: 0.8, sensitivity: .medium, source: "focus_mode")
    }

    private func calendarCandidates(from records: [ScoutRecord]) -> [MemoryCandidate] {
        guard !records.isEmpty else { return [] }
        return [
            MemoryCandidate(
                text: "Calendar cadence: \(records.map(\.content).joined(separator: " "))",
                category: "workflow",
                confidence: 0.85,
                sensitivity: .medium,
                evidence: records.map { EvidencePointer(source: "calendar", detail: $0.content) }
            ),
        ]
    }

    private func reminderCandidates(from records: [ScoutRecord]) -> [MemoryCandidate] {
        primaryRecordCandidate(
            from: records,
            textPrefix: "Reminder backlog:",
            category: "workflow",
            confidence: 0.8,
            sensitivity: .medium,
            source: "reminders"
        )
    }

    private func sleepCandidates(from records: [ScoutRecord]) -> [MemoryCandidate] {
        primaryRecordCandidate(from: records, category: "wellbeing", confidence: 0.9, sensitivity: .high, source: "health_sleep")
    }

    private func recentDocumentCandidates(from records: [ScoutRecord]) -> [MemoryCandidate] {
        guard !records.isEmpty else { return [] }
        return [
            MemoryCandidate(
                text: "User actively edits documents through \(records.count) tracked apps recently.",
                category: "workflow",
                confidence: 0.75,
                sensitivity: .medium,
                evidence: records.prefix(5).map {
                    EvidencePointer(source: "recent_documents", detail: $0.metadata["list"] ?? $0.content)
                }
            ),
        ]
    }

    private func personalizationSignalCandidates(from records: [ScoutRecord]) -> [MemoryCandidate] {
        let recurringApps = records.filter {
            $0.metadata["signal_kind"] == PersonalizationSignalKind.appFocus.rawValue &&
                (Double($0.metadata["weight"] ?? "0") ?? 0) >= 15
        }
        guard !recurringApps.isEmpty else { return [] }
        let labels = recurringApps.prefix(5).map(\.content).joined(separator: "; ")
        return [
            MemoryCandidate(
                text: "Recurring work surface signals: \(labels).",
                category: "workflow",
                confidence: 0.78,
                sensitivity: .low,
                evidence: recurringApps.prefix(5).map {
                    EvidencePointer(source: "personalization_signals", detail: $0.content)
                },
                recommendedTTL: 14 * 24 * 60 * 60
            ),
        ]
    }

    private func primaryRecordCandidate(
        from records: [ScoutRecord],
        textPrefix: String? = nil,
        category: String,
        confidence: Double,
        sensitivity: Sensitivity,
        source: String
    ) -> [MemoryCandidate] {
        guard let record = records.first else { return [] }
        let text = textPrefix.map { "\($0) \(record.content)" } ?? record.content
        return [
            MemoryCandidate(
                text: text,
                category: category,
                confidence: confidence,
                sensitivity: sensitivity,
                evidence: [EvidencePointer(source: source, detail: record.content)]
            ),
        ]
    }

    private static let developmentApps: Set<String> = [
        "Xcode", "Terminal", "iTerm", "Docker", "Postman", "VS Code",
        "Visual Studio Code", "Sublime Text", "IntelliJ IDEA", "Android Studio",
        "Cursor", "Warp", "Ghostty", "Rio",
    ]

    private static let creativeApps: Set<String> = [
        "Figma", "Sketch", "Final Cut Pro", "Logic Pro", "Blender",
        "Adobe Photoshop", "Adobe Illustrator", "DaVinci Resolve",
    ]

    private static let productivityApps: Set<String> = [
        "Obsidian", "Notion", "Craft", "Bear", "Things", "Todoist",
        "Linear", "Slack", "Discord", "Telegram",
    ]

    private func generateReport(records: [ScoutRecord], candidates: [MemoryCandidate]) -> String {
        let dateStr = ISO8601DateFormatter().string(from: Date())
        let deviceRecords = records.filter { $0.kind == .deviceInfo }
        let apps = records.filter { $0.kind == .installedApp }
        let projects = records.filter { $0.kind == .projectInfo }
        let gitRepos = records.filter { $0.kind == .gitRepo }

        return """
        ════════════════════════════════════════════════
        Swoosh Setup Report
        \(dateStr)
        ════════════════════════════════════════════════

        DEVICE
        \(deviceRecords.map { "  • \($0.content)" }.joined(separator: "\n"))

        INSTALLED APPS (\(apps.count) detected)
        \(apps.prefix(20).map { "  • \($0.content)" }.joined(separator: "\n"))
        \(apps.count > 20 ? "  … and \(apps.count - 20) more" : "")

        PROJECTS (\(projects.count) detected)
        \(projects.map { "  • \($0.content)" }.joined(separator: "\n"))

        GIT REPOS (\(gitRepos.count) detected)
        \(gitRepos.map { "  • \($0.content)" }.joined(separator: "\n"))

        MEMORY CANDIDATES (\(candidates.count))
        \(candidates.enumerated().map { "  \($0.offset + 1). [\($0.element.category)] \($0.element.text)" }.joined(separator: "\n"))

        ════════════════════════════════════════════════
        """
    }
}

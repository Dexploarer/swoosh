// SwooshScout/Pipeline+CandidateGenerators.swift — 0.9S Per-RecordKind candidate generators
//
// One method per RecordKind that converts redacted ScoutRecords into
// MemoryCandidates. Extracted from Pipeline.swift so the orchestration
// file stays focused on the run-loop. Also owns the canonical
// app-name buckets (development / creative / productivity) used by
// `installedAppCandidates`, and the human-readable setup-report builder.

import Foundation

extension ScoutPipeline {

    func generateCandidates(from records: [ScoutRecord]) -> [MemoryCandidate] {
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
            personalizationSignalCandidates(from: recordsMatching(.personalizationSignal, in: records))
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
            )
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
            )
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
            )
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
            )
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
            )
        ]
    }

    private func focusModeCandidates(from records: [ScoutRecord]) -> [MemoryCandidate] {
        primaryRecordCandidate(
            from: records,
            category: "preference",
            confidence: 0.8,
            sensitivity: .medium,
            source: "focus_mode"
        )
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
            )
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
        primaryRecordCandidate(
            from: records,
            category: "wellbeing",
            confidence: 0.9,
            sensitivity: .high,
            source: "health_sleep"
        )
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
            )
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
            )
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
            )
        ]
    }

    static let developmentApps: Set<String> = [
        "Xcode", "Terminal", "iTerm", "Docker", "Postman", "VS Code",
        "Visual Studio Code", "Sublime Text", "IntelliJ IDEA", "Android Studio",
        "Cursor", "Warp", "Ghostty", "Rio"
    ]

    static let creativeApps: Set<String> = [
        "Figma", "Sketch", "Final Cut Pro", "Logic Pro", "Blender",
        "Adobe Photoshop", "Adobe Illustrator", "DaVinci Resolve"
    ]

    static let productivityApps: Set<String> = [
        "Obsidian", "Notion", "Craft", "Bear", "Things", "Todoist",
        "Linear", "Slack", "Discord", "Telegram"
    ]

    func generateReport(records: [ScoutRecord], candidates: [MemoryCandidate]) -> String {
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
        \(Self.renderCandidateLines(candidates))

        ════════════════════════════════════════════════
        """
    }

    private static func renderCandidateLines(_ candidates: [MemoryCandidate]) -> String {
        candidates
            .enumerated()
            .map { "  \($0.offset + 1). [\($0.element.category)] \($0.element.text)" }
            .joined(separator: "\n")
    }
}

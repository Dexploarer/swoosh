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

public struct ScoutPipeline: Sendable {
    private let sources: [any ScoutSource]
    private let redactor: SecretRedactor

    public init(sources: [any ScoutSource]) {
        self.sources = sources
        self.redactor = SecretRedactor()
    }

    /// Run the full pipeline: scan → redact → generate candidates → produce report
    public func run(depth: PersonalizationDepth, log: @Sendable (String) -> Void = { _ in }) async throws -> ScoutPipelineResult {
        let progress = ScanProgress()
        var allRecords: [ScoutRecord] = []
        var sourcesScanned = 0
        var totalRedacted = 0

        // Phase 1: Scan each source
        for source in sources {
            guard shouldInclude(source, depth: depth) else {
                log("  ○ \(source.displayName) — skipped (sensitivity: \(source.sensitivity.rawValue))")
                continue
            }

            let permStatus = try await source.checkPermission()
            var hasPermission = (permStatus == .granted)

            if !hasPermission {
                log("  ⟳ Requesting permission for \(source.displayName)...")
                let requested = try await source.requestPermission()
                hasPermission = (requested == .granted)
            }

            guard hasPermission else {
                log("  ✗ \(source.displayName) — permission denied")
                continue
            }

            log("  ⟳ Scanning \(source.displayName)...")
            let records = try await source.scan(progress: progress)
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
        let candidates = generateCandidates(from: redactedRecords)
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
        var candidates: [MemoryCandidate] = []

        // ── Developer profile detection ──────────────────────────────
        let apps = records.filter { $0.kind == .installedApp }
        if !apps.isEmpty {
            let appNames = apps.map(\.content)
            let devApps = appNames.filter {
                ["Xcode", "Terminal", "iTerm", "Docker", "Postman", "VS Code",
                 "Visual Studio Code", "Sublime Text", "IntelliJ IDEA", "Android Studio",
                 "Cursor", "Warp", "Ghostty", "Rio"].contains($0)
            }
            let creativeApps = appNames.filter {
                ["Figma", "Sketch", "Final Cut Pro", "Logic Pro", "Blender",
                 "Adobe Photoshop", "Adobe Illustrator", "DaVinci Resolve"].contains($0)
            }
            let productivityApps = appNames.filter {
                ["Obsidian", "Notion", "Craft", "Bear", "Things", "Todoist",
                 "Linear", "Slack", "Discord", "Telegram"].contains($0)
            }

            if !devApps.isEmpty {
                candidates.append(MemoryCandidate(
                    text: "User is a developer. Development tools: \(devApps.joined(separator: ", ")).",
                    category: "profile",
                    confidence: 0.9,
                    sensitivity: .low,
                    evidence: devApps.map { EvidencePointer(source: "installed_apps", detail: $0) }
                ))
            }
            if !creativeApps.isEmpty {
                candidates.append(MemoryCandidate(
                    text: "User works with creative/design tools: \(creativeApps.joined(separator: ", ")).",
                    category: "profile",
                    confidence: 0.85,
                    sensitivity: .low,
                    evidence: creativeApps.map { EvidencePointer(source: "installed_apps", detail: $0) }
                ))
            }
            if !productivityApps.isEmpty {
                candidates.append(MemoryCandidate(
                    text: "User uses productivity tools: \(productivityApps.joined(separator: ", ")).",
                    category: "profile",
                    confidence: 0.85,
                    sensitivity: .low,
                    evidence: productivityApps.map { EvidencePointer(source: "installed_apps", detail: $0) }
                ))
            }
        }

        // ── Project detection ────────────────────────────────────────
        let projects = records.filter { $0.kind == .projectInfo }
        if !projects.isEmpty {
            let swiftProjects = projects.filter { $0.metadata["type"] == "Swift Package" }
            if !swiftProjects.isEmpty {
                candidates.append(MemoryCandidate(
                    text: "User has \(swiftProjects.count) Swift package(s): \(swiftProjects.map(\.content).joined(separator: ", ")).",
                    category: "project",
                    confidence: 0.9,
                    sensitivity: .low,
                    evidence: swiftProjects.map { EvidencePointer(source: "project_folders", detail: $0.metadata["path"] ?? $0.content) }
                ))
            }

            let nodeProjects = projects.filter { $0.metadata["type"] == "Node.js" }
            if !nodeProjects.isEmpty {
                candidates.append(MemoryCandidate(
                    text: "User has \(nodeProjects.count) Node.js project(s): \(nodeProjects.map(\.content).joined(separator: ", ")).",
                    category: "project",
                    confidence: 0.85,
                    sensitivity: .low,
                    evidence: nodeProjects.map { EvidencePointer(source: "project_folders", detail: $0.content) }
                ))
            }
        }

        // ── Git / remote detection ───────────────────────────────────
        let gitRepos = records.filter { $0.kind == .gitRepo }
        let githubRepos = gitRepos.filter { ($0.metadata["remote"] ?? "").contains("github.com") }
        if !githubRepos.isEmpty {
            candidates.append(MemoryCandidate(
                text: "User has \(githubRepos.count) GitHub repo(s) locally.",
                category: "profile",
                confidence: 0.9,
                sensitivity: .low,
                evidence: githubRepos.map { EvidencePointer(source: "git_repos", detail: $0.content) }
            ))
        }

        // ── Shell / tooling summary ──────────────────────────────────
        let shellRecords = records.filter { $0.kind == .shellEnvironment }
        for r in shellRecords {
            if r.content.contains("Tools in PATH") {
                candidates.append(MemoryCandidate(
                    text: "Developer environment: \(r.content)",
                    category: "preference",
                    confidence: 0.8,
                    sensitivity: .low,
                    evidence: [EvidencePointer(source: "shell_env", detail: r.content)]
                ))
            }
        }

        // ── Device summary ───────────────────────────────────────────
        let deviceRecords = records.filter { $0.kind == .deviceInfo }
        if !deviceRecords.isEmpty {
            let deviceSummary = deviceRecords.map(\.content).joined(separator: ". ")
            candidates.append(MemoryCandidate(
                text: "Device: \(deviceSummary)",
                category: "device",
                confidence: 1.0,
                sensitivity: .low,
                evidence: [EvidencePointer(source: "device", detail: "system info")]
            ))
        }

        return candidates
    }

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

// SwooshScout/ScoutPipeline.swift — Scout orchestrator and report
import Foundation

// MARK: - Scout orchestrator

/// Runs the personalization scan pipeline.
public actor SwooshScout {
    private let sources: [any ScoutSource]
    private let redactor: SecretRedactor
    private let progress: ScanProgress

    public init(sources: [any ScoutSource]) {
        self.sources = sources
        self.redactor = SecretRedactor()
        self.progress = ScanProgress()
    }

    /// Run the full scan → redact → classify → generate candidates pipeline.
    public func scan(depth: PersonalizationDepth) async throws -> ScoutReport {
        let applicableSources = sources.filter { shouldInclude($0, depth: depth) }
        var allRecords: [ScoutRecord] = []
        var sourceResults: [SourceScanResult] = []

        for source in applicableSources {
            let permStatus = try await source.checkPermission()
            var hasPermission = (permStatus == .granted)

            if !hasPermission {
                let requested = try await source.requestPermission()
                hasPermission = (requested == .granted)
            }

            guard hasPermission else {
                sourceResults.append(SourceScanResult(
                    sourceID: source.id,
                    displayName: source.displayName,
                    status: .denied,
                    recordCount: 0
                ))
                continue
            }

            do {
                let records = try await source.scan(progress: progress)
                let redacted = records.map { redactor.redact($0) }
                allRecords.append(contentsOf: redacted)
                sourceResults.append(SourceScanResult(
                    sourceID: source.id,
                    displayName: source.displayName,
                    status: .completed,
                    recordCount: redacted.count
                ))
            } catch {
                sourceResults.append(SourceScanResult(
                    sourceID: source.id,
                    displayName: source.displayName,
                    status: .failed(error.localizedDescription),
                    recordCount: 0
                ))
            }
        }

        // Generate memory candidates from records
        let candidates = generateCandidates(from: allRecords)

        return ScoutReport(
            timestamp: Date(),
            depth: depth,
            sourceResults: sourceResults,
            totalRecords: allRecords.count,
            memoryCandidates: candidates
        )
    }

    private func shouldInclude(_ source: any ScoutSource, depth: PersonalizationDepth) -> Bool {
        switch depth {
        case .minimal:
            return source.sensitivity <= .low
        case .recommended:
            return source.sensitivity <= .medium
        case .deep:
            return source.sensitivity <= .high
        case .custom:
            return true // caller filters
        }
    }

    private func generateCandidates(from records: [ScoutRecord]) -> [MemoryCandidate] {
        // Simple heuristic candidate generation.
        // In production, use Foundation Models / local MLX for extraction.
        var candidates: [MemoryCandidate] = []

        // Group installed apps → detect developer/creative/productivity profile
        let apps = records.filter { $0.kind == .installedApp }
        if !apps.isEmpty {
            let appNames = apps.map(\.content)
            let devApps = appNames.filter { ["Xcode", "Terminal", "Docker", "Postman", "VS Code", "Sublime Text"].contains($0) }
            if !devApps.isEmpty {
                candidates.append(MemoryCandidate(
                    text: "User is a developer. Has: \(devApps.joined(separator: ", ")).",
                    category: "preference",
                    confidence: 0.9,
                    sensitivity: .low,
                    evidence: devApps.map { EvidencePointer(source: "installed_apps", detail: $0) }
                ))
            }
        }

        // Detect calendar patterns
        let calRecords = records.filter { $0.kind == .calendarPattern }
        for record in calRecords {
            candidates.append(MemoryCandidate(
                text: record.content,
                category: "preference",
                confidence: 0.7,
                sensitivity: .medium,
                evidence: [EvidencePointer(source: "calendar", detail: "Pattern analysis")]
            ))
        }

        // Detect project folders
        let projects = records.filter { $0.kind == .projectInfo }
        for project in projects {
            candidates.append(MemoryCandidate(
                text: project.content,
                category: "project",
                confidence: 0.8,
                sensitivity: .low,
                evidence: [EvidencePointer(source: project.sourceID, detail: project.metadata["path"] ?? "")]
            ))
        }

        return candidates
    }
}

// MARK: - Scout report

public struct ScoutReport: Sendable {
    public let timestamp: Date
    public let depth: PersonalizationDepth
    public let sourceResults: [SourceScanResult]
    public let totalRecords: Int
    public let memoryCandidates: [MemoryCandidate]
}

public struct SourceScanResult: Sendable {
    public let sourceID: String
    public let displayName: String
    public let status: SourceScanStatus
    public let recordCount: Int
}

public enum SourceScanStatus: Sendable {
    case completed
    case denied
    case skipped
    case failed(String)
}

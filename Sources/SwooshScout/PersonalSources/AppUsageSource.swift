// SwooshScout/PersonalSources/AppUsageSource.swift — 0.9S App focus history source
//
// macOS-only deep-personalization source. Reads the JSONL log written by
// `AppUsageRecorder` and summarises per-app focus time over a configurable
// window (default 7 days). Aggregated bundle-level only — no document or
// window-title content is exported, in line with the module's
// aggregate-only contract.

import Foundation

public struct AppUsageSource: ScoutSource {
    public let id = "app_usage"
    public let displayName = "App Usage History"
    public let description = "Per-app focus time tracked by the running daemon (macOS equivalent of Screen Time)."
    public let sensitivity = Sensitivity.high
    public let requiredPermissions = ["app_usage.read"]

    public let logURL: URL
    public let window: TimeInterval

    public init(
        logURL: URL = AppUsageRecorder.defaultLogURL(),
        window: TimeInterval = 7 * 24 * 60 * 60
    ) {
        self.logURL = logURL
        self.window = window
    }

    public func checkPermission() async throws -> SourcePermissionStatus {
        // The recorder writes to a file in our own ~/.swoosh — no OS
        // permission gate. Permission here is "did the daemon log
        // anything yet?"
        FileManager.default.fileExists(atPath: logURL.path) ? .granted : .denied
    }

    public func requestPermission() async throws -> SourcePermissionStatus {
        try await checkPermission()
    }

    public func scan(progress: ScanProgress) async throws -> [ScoutRecord] {
        guard let data = try? Data(contentsOf: logURL),
              let text = String(data: data, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let cutoff = Date().addingTimeInterval(-window)
        var totals: [String: (display: String, seconds: Double, sessions: Int, last: Date)] = [:]
        for line in text.split(separator: "\n") where !line.isEmpty {
            guard let lineData = String(line).data(using: .utf8),
                  let event = try? decoder.decode(AppFocusEvent.self, from: lineData),
                  event.endedAt >= cutoff else { continue }
            var entry = totals[event.bundleID] ?? (event.displayName, 0, 0, .distantPast)
            entry.seconds += event.duration
            entry.sessions += 1
            entry.last = max(entry.last, event.endedAt)
            totals[event.bundleID] = entry
        }

        return totals
            .sorted { $0.value.seconds > $1.value.seconds }
            .map { (bundleID, entry) in
                ScoutRecord(
                    sourceID: id, kind: .appUsage, sensitivity: .high,
                    content: "\(entry.display): \(prettyMinutes(entry.seconds)) over \(entry.sessions) session(s)",
                    metadata: [
                        "bundle_id": bundleID,
                        "seconds": String(Int(entry.seconds)),
                        "sessions": String(entry.sessions),
                        "last_focused": ISO8601DateFormatter().string(from: entry.last),
                        "window_days": String(Int(window / 86400))
                    ]
                )
            }
    }

    private func prettyMinutes(_ seconds: Double) -> String {
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(minutes)m" }
        let h = minutes / 60
        let m = minutes % 60
        return "\(h)h\(m)m"
    }
}
